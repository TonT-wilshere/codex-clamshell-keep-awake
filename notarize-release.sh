#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="$SCRIPT_DIR/build/合盖工作.app"
RELEASE_DIR="$SCRIPT_DIR/release"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SCRIPT_DIR/Info.plist")"
BASE_NAME="Clamshell-Awake-${VERSION}-macOS-Universal"
DMG_PATH="$RELEASE_DIR/${BASE_NAME}.dmg"
ZIP_PATH="$RELEASE_DIR/${BASE_NAME}.zip"
CHECKSUM_PATH="$RELEASE_DIR/SHA256SUMS.txt"
NOTARY_WORK="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/clamshell-notary.XXXXXX")"
trap '/bin/rm -rf "$NOTARY_WORK"' EXIT

/bin/mkdir -p "$RELEASE_DIR"

: "${CODESIGN_IDENTITY:?Set CODESIGN_IDENTITY to your Developer ID Application identity.}"
: "${NOTARYTOOL_PROFILE:?Set NOTARYTOOL_PROFILE to a stored notarytool Keychain profile.}"

if [[ "$CODESIGN_IDENTITY" != Developer\ ID\ Application:* ]]; then
  /bin/echo "CODESIGN_IDENTITY must begin with 'Developer ID Application:'." >&2
  exit 1
fi

if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "$CODESIGN_IDENTITY"; then
  /bin/echo "The requested Developer ID identity is not available in this Keychain." >&2
  exit 1
fi

/bin/echo "1/7 Building and signing with Hardened Runtime…"
CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$SCRIPT_DIR/build.sh" >/dev/null
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

/bin/echo "2/7 Submitting the signed app to Apple…"
APP_UPLOAD="$NOTARY_WORK/${BASE_NAME}-app.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$APP_UPLOAD"
APP_RESULT="$(/usr/bin/xcrun notarytool submit "$APP_UPLOAD" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait \
  --output-format plist)"
APP_STATUS="$(/bin/echo "$APP_RESULT" | /usr/bin/plutil -extract status raw -o - -)"
APP_SUBMISSION_ID="$(/bin/echo "$APP_RESULT" | /usr/bin/plutil -extract id raw -o - -)"
/bin/echo "App notarization status: $APP_STATUS ($APP_SUBMISSION_ID)"
/usr/bin/xcrun notarytool log "$APP_SUBMISSION_ID" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  "$RELEASE_DIR/notarization-app-log.json"
if [[ "$APP_STATUS" != "Accepted" ]]; then
  /bin/echo "Apple rejected the app. Review release/notarization-app-log.json." >&2
  exit 1
fi

/bin/echo "3/7 Stapling and validating the app ticket…"
/usr/bin/xcrun stapler staple "$APP_PATH"
/usr/bin/xcrun stapler validate "$APP_PATH"

/bin/echo "4/7 Packaging the stapled app…"
SKIP_BUILD=1 CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$SCRIPT_DIR/package-universal.sh" >/dev/null

/bin/echo "5/7 Submitting the signed DMG to Apple…"
DMG_RESULT="$(/usr/bin/xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  --wait \
  --output-format plist)"
DMG_STATUS="$(/bin/echo "$DMG_RESULT" | /usr/bin/plutil -extract status raw -o - -)"
DMG_SUBMISSION_ID="$(/bin/echo "$DMG_RESULT" | /usr/bin/plutil -extract id raw -o - -)"
/bin/echo "DMG notarization status: $DMG_STATUS ($DMG_SUBMISSION_ID)"
/usr/bin/xcrun notarytool log "$DMG_SUBMISSION_ID" \
  --keychain-profile "$NOTARYTOOL_PROFILE" \
  "$RELEASE_DIR/notarization-dmg-log.json"
if [[ "$DMG_STATUS" != "Accepted" ]]; then
  /bin/echo "Apple rejected the DMG. Review release/notarization-dmg-log.json." >&2
  exit 1
fi

/bin/echo "6/7 Stapling the DMG and refreshing checksums…"
/usr/bin/xcrun stapler staple "$DMG_PATH"
/usr/bin/xcrun stapler validate "$DMG_PATH"
(
  cd "$RELEASE_DIR"
  /usr/bin/shasum -a 256 "$(basename "$ZIP_PATH")" "$(basename "$DMG_PATH")" > "$(basename "$CHECKSUM_PATH")"
)

/bin/echo "7/7 Running Gatekeeper verification…"
/usr/sbin/spctl --assess --type execute --verbose=2 "$APP_PATH"
/usr/sbin/spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"

/bin/echo "Notarized release ready:"
/bin/echo "$ZIP_PATH"
/bin/echo "$DMG_PATH"
/bin/echo "$CHECKSUM_PATH"
