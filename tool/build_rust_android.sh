#!/usr/bin/env bash
set -euo pipefail

readonly repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly rust_manifest="$repo_root/rust/Cargo.toml"
readonly jni_libs_directory="$repo_root/android/app/src/main/jniLibs"
readonly android_api="${OPENLOGTOOL_ANDROID_API:-24}"
readonly cargo_ndk_version="4.1.2"
readonly rust_targets=(
  aarch64-linux-android
  armv7-linux-androideabi
  x86_64-linux-android
)
readonly android_abis=(
  arm64-v8a
  armeabi-v7a
  x86_64
)

if ! command -v cargo >/dev/null 2>&1; then
  echo "error: cargo is required to build the Android native libraries" >&2
  exit 1
fi

if ! command -v rustup >/dev/null 2>&1; then
  echo "error: rustup is required to manage the Android Rust targets" >&2
  exit 1
fi

if ! installed_cargo_ndk_version="$(cargo ndk --version 2>/dev/null)"; then
  echo "error: cargo-ndk $cargo_ndk_version is required" >&2
  echo "install it with: cargo install cargo-ndk --version $cargo_ndk_version --locked" >&2
  exit 1
fi

if [[ "$installed_cargo_ndk_version" != "cargo-ndk $cargo_ndk_version" ]]; then
  echo "error: expected cargo-ndk $cargo_ndk_version, found $installed_cargo_ndk_version" >&2
  echo "install the pinned version with: cargo install cargo-ndk --version $cargo_ndk_version --locked --force" >&2
  exit 1
fi

mapfile -t installed_rust_targets < <(rustup target list --installed)
for target in "${rust_targets[@]}"; do
  if [[ ! " ${installed_rust_targets[*]} " =~ [[:space:]]${target}[[:space:]] ]]; then
    echo "error: Rust target $target is not installed" >&2
    echo "install all Android targets with: rustup target add ${rust_targets[*]}" >&2
    exit 1
  fi
done

# cargo-ndk 4.1.2 resolves metadata from the current directory before it
# applies --manifest-path, so invoke it from the Rust crate itself.
cd "$repo_root/rust"

cargo ndk \
  --platform "$android_api" \
  -t arm64-v8a \
  -t armeabi-v7a \
  -t x86_64 \
  -o "$jni_libs_directory" \
  --manifest-path "$rust_manifest" \
  build \
  --release \
  --locked \
  --lib

for abi in "${android_abis[@]}"; do
  library="$jni_libs_directory/$abi/libopenlogtool_core.so"
  if [[ ! -s "$library" ]]; then
    echo "error: cargo-ndk did not produce $library" >&2
    exit 1
  fi
done

echo "Android Rust libraries are ready in $jni_libs_directory"
