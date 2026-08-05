#!/bin/bash

# Build the Rust static library for every architecture requested by Xcode and
# merge the slices into a single archive that the Runner target links against.
# This script is invoked by the Runner target, but can also be run from a macOS
# shell when the Xcode output variables are set.

set -euo pipefail

readonly LIBRARY_NAME="libopenlogtool_core.a"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
readonly RUST_ROOT="$PROJECT_ROOT/rust"
readonly MANIFEST_PATH="$RUST_ROOT/Cargo.toml"
readonly OUTPUT_DIR="$PROJECT_ROOT/ios/Runner/rustlibs"
readonly MERGED_LIBRARY="$OUTPUT_DIR/$LIBRARY_NAME"

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

  fail "cargo was not found; install the Rust toolchain before building iOS"
}

# Resolve the Rust target for one requested architecture. Xcode passes the
# platform in PLATFORM_NAME: iphoneos builds the device slice, while
# iphonesimulator slices map to the simulator targets.
ios_target_for() {
  local platform="$1"
  local architecture="$2"
  case "$platform" in
    iphoneos)
      case "$architecture" in
        arm64 | arm64e | aarch64)
          printf '%s\n' "aarch64-apple-ios"
          ;;
        *)
          fail "unsupported iOS device architecture: $architecture"
          ;;
      esac
      ;;
    iphonesimulator)
      case "$architecture" in
        arm64 | arm64e | aarch64)
          printf '%s\n' "aarch64-apple-ios-sim"
          ;;
        x86_64)
          printf '%s\n' "x86_64-apple-ios"
          ;;
        *)
          fail "unsupported iOS simulator architecture: $architecture"
          ;;
      esac
      ;;
    *)
      fail "unsupported iOS platform: $platform"
      ;;
  esac
}

[[ "$(uname -s)" == "Darwin" ]] || fail "this script must run on macOS"
[[ -f "$MANIFEST_PATH" ]] || fail "Rust manifest not found: $MANIFEST_PATH"

readonly CARGO_BIN="$(find_cargo)"
readonly CONFIGURATION_NAME="${CONFIGURATION:-Release}"

# 固定 iOS 部署目标：rusqlite bundled 会编译 sqlite3.c，cc crate 读取该环境
# 变量；缺失时 clang/rustc 各用默认值可能不一致导致链接报
# "object file built for newer iOS version"。
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-13.0}"

if [[ "$CONFIGURATION_NAME" == Debug* ]]; then
  readonly CARGO_PROFILE="debug"
  readonly CARGO_RELEASE_FLAG=""
else
  readonly CARGO_PROFILE="release"
  readonly CARGO_RELEASE_FLAG="--release"
fi

# When run outside of Xcode, PLATFORM_NAME and ARCHS are usually unset; fall
# back to a single arm64 device slice like `flutter build ios` would produce.
platform_name="${PLATFORM_NAME:-iphoneos}"
requested_architectures="${ARCHS:-${NATIVE_ARCH_ACTUAL:-arm64}}"
read -r -a architecture_list <<< "$requested_architectures"
[[ "${#architecture_list[@]}" -gt 0 ]] || fail "no iOS architectures were requested"

target_list=()
seen_targets=" "
for architecture in "${architecture_list[@]}"; do
  target="$(ios_target_for "$platform_name" "$architecture")"
  if [[ "$seen_targets" != *" $target "* ]]; then
    target_list+=("$target")
    seen_targets="$seen_targets$target "
  fi
done

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

mkdir -p "$OUTPUT_DIR"

if [[ "${#library_slices[@]}" -eq 1 ]]; then
  cp -f "${library_slices[0]}" "$MERGED_LIBRARY"
else
  xcrun lipo -create "${library_slices[@]}" -output "$MERGED_LIBRARY"
fi

for architecture in "${architecture_list[@]}"; do
  case "$architecture" in
    arm64e | aarch64) architecture="arm64" ;;
  esac
  xcrun lipo "$MERGED_LIBRARY" -verify_arch "$architecture"
done

echo "Linked $MERGED_LIBRARY"
xcrun lipo -info "$MERGED_LIBRARY"
