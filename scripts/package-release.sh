#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build.sh
APP="$PWD/build/醒着.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
RELEASE_DIR="$PWD/build/releases"
STAGING_ROOT="$(mktemp -d "$PWD/build/package.XXXXXX")"
trap 'rm -rf "$STAGING_ROOT"' EXIT
STAGE="$STAGING_ROOT/Xingzhe-$VERSION"
ARCHIVE="$RELEASE_DIR/Xingzhe-$VERSION-macOS-arm64.zip"
mkdir -p "$STAGE" "$RELEASE_DIR"

ditto --norsrc --noextattr "$APP" "$STAGE/醒着.app"
cp README.md README.zh-CN.md LICENSE NOTICE CHANGELOG.md "$STAGE/"
codesign --verify --deep --strict "$STAGE/醒着.app"
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$ARCHIVE"
(
    cd "$RELEASE_DIR"
    shasum -a 256 "$(basename "$ARCHIVE")" > SHA256SUMS.txt
)
printf 'Packaged: %s\n' "$ARCHIVE"
