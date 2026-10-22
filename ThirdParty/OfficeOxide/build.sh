#!/bin/bash
set -euo pipefail
# 수동 재빌드용. 앱·CI 빌드에는 Rust가 필요하지 않다.
root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
git clone --no-checkout https://github.com/yfedoseev/office_oxide.git "$work/source"
git -C "$work/source" checkout --detach 5d183f4de990de254f32976bf952e548bcd25972
cd "$work/source"
git apply "$root/compat.patch"
export CARGO_TARGET_DIR="$work/target"
cargo build --locked --release --lib --target aarch64-apple-ios \
  --target aarch64-apple-ios-sim --target x86_64-apple-ios
lipo -create "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/liboffice_oxide.a" \
  "$CARGO_TARGET_DIR/x86_64-apple-ios/release/liboffice_oxide.a" -output "$work/simulator.a"
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/liboffice_oxide.a" -headers "$root/include" \
  -library "$work/simulator.a" -headers "$root/include" -output "$work/OfficeOxide.xcframework"
rm -rf "$root/OfficeOxide.xcframework"
mv "$work/OfficeOxide.xcframework" "$root/OfficeOxide.xcframework"
