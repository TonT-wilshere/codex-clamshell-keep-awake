#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_NAME="合盖工作.app"
APP_DIR="$SCRIPT_DIR/build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
COMPATIBLE_SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX13.1.sdk"
if [[ -d "$COMPATIBLE_SDK" ]]; then
  SDK_PATH="$COMPATIBLE_SDK"
else
  SDK_PATH="$(/usr/bin/xcrun --show-sdk-path)"
fi
MODULE_CACHE="${TMPDIR:-/tmp}/keep-codex-awake-module-cache"
BUILD_WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/keep-awake-build.XXXXXX")"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
trap '/bin/rm -rf "$BUILD_WORK"' EXIT

/bin/mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$MODULE_CACHE"
SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -target arm64-apple-macosx12.0 \
  -O \
  -framework Cocoa \
  -framework IOKit \
  "$SCRIPT_DIR/Sources/KeepCodexAwake.swift" \
  -o "$BUILD_WORK/KeepCodexAwake-arm64"

SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -target x86_64-apple-macosx12.0 \
  -O \
  -framework Cocoa \
  -framework IOKit \
  "$SCRIPT_DIR/Sources/KeepCodexAwake.swift" \
  -o "$BUILD_WORK/KeepCodexAwake-x86_64"

/usr/bin/lipo -create \
  "$BUILD_WORK/KeepCodexAwake-arm64" \
  "$BUILD_WORK/KeepCodexAwake-x86_64" \
  -output "$MACOS_DIR/KeepCodexAwake"

ICON_WORK="$BUILD_WORK/icon"
ICONSET="$ICON_WORK/AppIcon.iconset"
MASTER_ICON="$ICON_WORK/AppIcon-1024.png"
/bin/mkdir -p "$ICONSET"

SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -O \
  -framework Cocoa \
  "$SCRIPT_DIR/Tools/IconRenderer.swift" \
  -o "$ICON_WORK/IconRenderer"

SWIFT_MODULECACHE_PATH="$MODULE_CACHE" \
CLANG_MODULE_CACHE_PATH="$MODULE_CACHE" \
/usr/bin/swiftc \
  -sdk "$SDK_PATH" \
  -module-cache-path "$MODULE_CACHE" \
  -O \
  "$SCRIPT_DIR/Tools/IconPacker.swift" \
  -o "$ICON_WORK/IconPacker"

"$ICON_WORK/IconRenderer" "$MASTER_ICON"
for spec in \
  '16 icon_16x16.png' \
  '32 icon_16x16@2x.png' \
  '32 icon_32x32.png' \
  '64 icon_32x32@2x.png' \
  '128 icon_128x128.png' \
  '256 icon_128x128@2x.png' \
  '256 icon_256x256.png' \
  '512 icon_256x256@2x.png' \
  '512 icon_512x512.png' \
  '1024 icon_512x512@2x.png'; do
  size="${spec%% *}"
  name="${spec#* }"
  /usr/bin/sips -z "$size" "$size" "$MASTER_ICON" --out "$ICONSET/$name" >/dev/null
done
"$ICON_WORK/IconPacker" "$RESOURCES_DIR/AppIcon.icns" \
  icp4 "$ICONSET/icon_16x16.png" \
  icp5 "$ICONSET/icon_32x32.png" \
  icp6 "$ICONSET/icon_32x32@2x.png" \
  ic07 "$ICONSET/icon_128x128.png" \
  ic08 "$ICONSET/icon_256x256.png" \
  ic09 "$ICONSET/icon_512x512.png" \
  ic10 "$ICONSET/icon_512x512@2x.png" \
  ic11 "$ICONSET/icon_16x16@2x.png" \
  ic12 "$ICONSET/icon_32x32@2x.png" \
  ic13 "$ICONSET/icon_128x128@2x.png" \
  ic14 "$ICONSET/icon_256x256@2x.png"

/usr/bin/ditto "$SCRIPT_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
if [[ "$CODESIGN_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_DIR"
else
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$CODESIGN_IDENTITY" \
    "$APP_DIR"
fi

/bin/echo "$APP_DIR"
