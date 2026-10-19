#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Info.plist")"
APP_PATH="$SCRIPT_DIR/build/合盖工作.app"
RELEASE_DIR="$SCRIPT_DIR/release"
BASE_NAME="合盖工作-${VERSION}-macOS-Universal"
ZIP_PATH="$RELEASE_DIR/${BASE_NAME}.zip"
DMG_PATH="$RELEASE_DIR/${BASE_NAME}.dmg"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/keep-awake-release.XXXXXX")"
trap '/bin/rm -rf "$STAGING_DIR"' EXIT

"$SCRIPT_DIR/build.sh" >/dev/null

architectures="$(/usr/bin/lipo -archs "$APP_PATH/Contents/MacOS/KeepCodexAwake")"
if [[ "$architectures" != *arm64* || "$architectures" != *x86_64* ]]; then
  /bin/echo "Universal binary verification failed: $architectures" >&2
  exit 1
fi

/bin/mkdir -p "$RELEASE_DIR" "$STAGING_DIR/合盖工作"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/合盖工作/合盖工作.app"
/usr/bin/ditto "$SCRIPT_DIR/Packaging/安装与安全说明.txt" "$STAGING_DIR/合盖工作/安装与安全说明.txt"
/bin/ln -s /Applications "$STAGING_DIR/合盖工作/应用程序"

/bin/rm -f "$ZIP_PATH" "$DMG_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$STAGING_DIR/合盖工作" "$ZIP_PATH"
/usr/bin/hdiutil create \
  -volname "合盖工作" \
  -srcfolder "$STAGING_DIR/合盖工作" \
  -ov \
  -format UDZO \
  "$DMG_PATH" >/dev/null

(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "${BASE_NAME}.zip" "${BASE_NAME}.dmg" > "$(basename "$CHECKSUM_PATH")"
)

/bin/echo "$ZIP_PATH"
/bin/echo "$DMG_PATH"
/bin/echo "$CHECKSUM_PATH"
