#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${CODE_SIGN_IDENTITY:?Release requires a Developer ID Application identity}"
: "${NOTARY_PROFILE:?Release requires a notarytool keychain profile}"
bash scripts/build.sh
APP="$PWD/build/醒着.app"
SPARKLE="$PWD/build/dependencies/Sparkle-2.9.6"
bash scripts/notarize-app.sh "$APP"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_DIR="$PWD/build/releases/$VERSION"
mkdir -p "$RELEASE_DIR"
ARCHIVE="$RELEASE_DIR/Xingzhe-$VERSION-macOS-arm64.zip"
NOTES="$PWD/updates/release-notes/$VERSION.html"
[[ -f "$NOTES" ]] || { echo "Missing release notes: $NOTES" >&2; exit 1; }
# Sparkle and manual downloads use the same app-only archive. Documents and
# licenses are embedded in Resources before the app is signed by build.sh.
ditto -c -k --keepParent --norsrc --noextattr "$APP" "$ARCHIVE"
cp "$NOTES" "$RELEASE_DIR/Xingzhe-$VERSION-macOS-arm64.html"
# Rebuild the latest-only feed, avoiding stale entries when packaging twice.
if [[ -f "$RELEASE_DIR/appcast.xml" ]]; then
    mv "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR/appcast.previous.xml.bak"
fi
"$SPARKLE/bin/generate_appcast" --account local.xingzhe.awake \
    --maximum-deltas 0 --maximum-versions 1 --embed-release-notes \
    --download-url-prefix "https://github.com/kokafang/Xingzhe/releases/download/v$VERSION/" \
    --full-release-notes-url "https://github.com/kokafang/Xingzhe/releases" \
    --link "https://github.com/kokafang/Xingzhe" \
    -o "$RELEASE_DIR/appcast.xml" "$RELEASE_DIR"
"$SPARKLE/bin/sign_update" --account local.xingzhe.awake --verify "$RELEASE_DIR/appcast.xml"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$ARCHIVE")" > SHA256SUMS.txt
)
python3 scripts/verify-update.py "$RELEASE_DIR/appcast.xml" "$ARCHIVE"
printf 'Packaged: %s\n' "$ARCHIVE"
