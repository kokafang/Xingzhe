#!/bin/bash
set -euo pipefail
APP="${1:?Usage: notarize-app.sh app-path}"
: "${NOTARY_PROFILE:?Set the notarytool keychain profile name}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/xingzhe-notary.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ditto -c -k --keepParent "$APP" "$WORK/submission.zip"
xcrun notarytool submit "$WORK/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
codesign --verify --deep --strict "$APP"
spctl --assess --type execute --verbose=4 "$APP"
