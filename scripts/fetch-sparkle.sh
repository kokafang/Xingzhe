#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=2.9.6
SHA256=52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192
ARCHIVE="$PWD/build/dependencies/Sparkle-$VERSION.tar.xz"
DEST="$PWD/build/dependencies/Sparkle-$VERSION"
mkdir -p "$(dirname "$ARCHIVE")"
if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --retry 3 --silent --show-error \
        "https://github.com/sparkle-project/Sparkle/releases/download/$VERSION/Sparkle-$VERSION.tar.xz" \
        --output "$ARCHIVE.partial"
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [[ ! -d "$DEST/Sparkle.framework" ]]; then
    mkdir -p "$DEST"
    tar -xJf "$ARCHIVE" -C "$DEST"
fi
codesign --verify --deep --strict "$DEST/Sparkle.framework"
