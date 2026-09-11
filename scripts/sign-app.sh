#!/bin/bash
set -euo pipefail
APP="${1:?Usage: sign-app.sh app-path}"
: "${CODE_SIGN_IDENTITY:?Set a Developer ID Application signing identity}"
SIGN=(--force --sign "$CODE_SIGN_IDENTITY" --options runtime --timestamp)
FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
codesign "${SIGN[@]}" "$FRAMEWORK/Versions/B/XPCServices/Installer.xpc"
codesign "${SIGN[@]}" --preserve-metadata=entitlements "$FRAMEWORK/Versions/B/XPCServices/Downloader.xpc"
codesign "${SIGN[@]}" "$FRAMEWORK/Versions/B/Autoupdate"
codesign "${SIGN[@]}" "$FRAMEWORK/Versions/B/Updater.app"
codesign "${SIGN[@]}" "$FRAMEWORK"
codesign "${SIGN[@]}" --identifier local.xingzhe.awake.helper "$APP/Contents/Library/HelperTools/AwakeHelper"
codesign "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
DETAILS="$(codesign -d --verbose=4 "$APP" 2>&1)"
[[ "$DETAILS" == *"Authority=Developer ID Application:"* && "$DETAILS" == *"runtime"* && "$DETAILS" == *"Timestamp="* ]] || {
    echo 'Release requires Developer ID Application, hardened runtime, and secure timestamp.' >&2
    exit 1
}
