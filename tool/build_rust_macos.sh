#!/bin/bash

# Build the Rust cdylib for every architecture requested by Xcode and embed it
# in the application bundle. This script is invoked by the Runner target, but
# can also be run from a macOS shell when the Xcode output variables are set.

set -euo pipefail

readonly LIBRARY_NAME="libopenlogtool_core.dylib"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly RUST_ROOT="$PROJECT_ROOT/rust"
readonly MANIFEST_PATH="$RUST_ROOT/Cargo.toml"

fail() {
  echo "error: $*" >&2
  exit 1
}

find_cargo() {
  if [[ -n "${CARGO:-}" && -x "${CARGO}" ]]; then
    printf '%s\n' "$CARGO"
    return
  fi

  if command -v cargo >/dev/null 2>&1; then
    command -v cargo
    return
  fi

  if [[ -x "${HOME:-}/.cargo/bin/cargo" ]]; then
    printf '%s\n' "$HOME/.cargo/bin/cargo"
    return
  fi

  fail "cargo was not found; install the Rust toolchain before building macOS"
}

normalize_architecture() {
  case "$1" in
    arm64 | arm64e | aarch64)
      printf '%s\n' "aarch64-apple-darwin"
      ;;
    x86_64)
      printf '%s\n' "x86_64-apple-darwin"
      ;;
    *)
      fail "unsupported macOS architecture: $1"
      ;;
  esac
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this script must run on macOS"
[[ -f "$MANIFEST_PATH" ]] || fail "Rust manifest not found: $MANIFEST_PATH"

readonly CARGO_BIN="$(find_cargo)"
readonly CONFIGURATION_NAME="${CONFIGURATION:-Release}"

if [[ "$CONFIGURATION_NAME" == Debug* ]]; then
  readonly CARGO_PROFILE="debug"
  readonly CARGO_RELEASE_FLAG=""
else
  readonly CARGO_PROFILE="release"
  readonly CARGO_RELEASE_FLAG="--release"
fi

# MACOS_RUST_ARCHS is useful in CI when a universal app is required. During a
# normal Xcode build ARCHS is already expanded to the architectures of the app.
requested_architectures="${MACOS_RUST_ARCHS:-${ARCHS:-${NATIVE_ARCH_ACTUAL:-$(uname -m)}}}"
read -r -a architecture_list <<< "$requested_architectures"
[[ "${#architecture_list[@]}" -gt 0 ]] || fail "no macOS architectures were requested"

target_list=()
seen_targets=" "
for architecture in "${architecture_list[@]}"; do
  target="$(normalize_architecture "$architecture")"
  if [[ "$seen_targets" != *" $target "* ]]; then
    target_list+=("$target")
    seen_targets="$seen_targets$target "
  fi
done

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.15}"

library_slices=()
for target in "${target_list[@]}"; do
  echo "Building $LIBRARY_NAME for $target ($CARGO_PROFILE)"
  cargo_arguments=(
    build
    --manifest-path "$MANIFEST_PATH"
    --locked
    --lib
    --target "$target"
  )
  if [[ -n "$CARGO_RELEASE_FLAG" ]]; then
    cargo_arguments+=("$CARGO_RELEASE_FLAG")
  fi

  "$CARGO_BIN" "${cargo_arguments[@]}"

  library_slice="$RUST_ROOT/target/$target/$CARGO_PROFILE/$LIBRARY_NAME"
  [[ -f "$library_slice" ]] || fail "cargo did not produce $library_slice"
  library_slices+=("$library_slice")
done

readonly TEMP_OUTPUT_DIR="${TARGET_TEMP_DIR:-$RUST_ROOT/target/macos-bundle}/openlogtool-rust"
readonly MERGED_LIBRARY="$TEMP_OUTPUT_DIR/$LIBRARY_NAME"
mkdir -p "$TEMP_OUTPUT_DIR"

if [[ "${#library_slices[@]}" -eq 1 ]]; then
  cp -f "${library_slices[0]}" "$MERGED_LIBRARY"
else
  xcrun lipo -create "${library_slices[@]}" -output "$MERGED_LIBRARY"
fi

for architecture in "${architecture_list[@]}"; do
  case "$architecture" in
    arm64e | aarch64) architecture="arm64" ;;
  esac
  xcrun lipo -verify_arch "$architecture" "$MERGED_LIBRARY"
done

# Keep the identity independent of the checkout path. Dart opens this dylib
# from Contents/Frameworks and the app already has the matching runpath.
xcrun install_name_tool -id "@rpath/$LIBRARY_NAME" "$MERGED_LIBRARY"

readonly FRAMEWORKS_DIR="${TARGET_BUILD_DIR:?TARGET_BUILD_DIR is required}/${FRAMEWORKS_FOLDER_PATH:-${CONTENTS_FOLDER_PATH:-${FULL_PRODUCT_NAME:-openlogtool.app}/Contents}/Frameworks}"
readonly BUNDLED_LIBRARY="$FRAMEWORKS_DIR/$LIBRARY_NAME"
mkdir -p "$FRAMEWORKS_DIR"
cp -f "$MERGED_LIBRARY" "$BUNDLED_LIBRARY"

# A dylib is nested code and must be signed before Xcode signs the outer app.
# Development and CI builds commonly use an ad-hoc identity ("-").
if [[ "${CODE_SIGNING_ALLOWED:-YES}" != "NO" ]]; then
  signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:-${CODE_SIGN_IDENTITY:--}}"
  [[ -n "$signing_identity" ]] || signing_identity="-"
  codesign --force --sign "$signing_identity" --timestamp=none "$BUNDLED_LIBRARY"
fi

echo "Embedded $BUNDLED_LIBRARY"
xcrun lipo -info "$BUNDLED_LIBRARY"
xcrun otool -D "$BUNDLED_LIBRARY"
