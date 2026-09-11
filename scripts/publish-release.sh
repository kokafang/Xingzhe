#!/bin/bash
# Publish binaries before the feed; clients must never see an unavailable ZIP.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ "$(git branch --show-current)" == main ]] || { echo 'Publish from main after reviewing and merging the change.' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit changes before publishing.' >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
TAG="v$VERSION"
RELEASE_DIR="$PWD/build/releases/$VERSION"
if gh release view "$TAG" --repo kokafang/Xingzhe >/dev/null 2>&1; then
    echo "Release $TAG already exists; do not overwrite signed release assets." >&2
    exit 1
fi
bash scripts/package-release.sh
if git rev-parse "$TAG" >/dev/null 2>&1; then
    [[ "$(git rev-list -n 1 "$TAG")" == "$(git rev-parse HEAD)" ]] || { echo 'Existing tag points elsewhere.' >&2; exit 1; }
else
    git tag -a "$TAG" -m "Xingzhe $VERSION"
fi
git push --atomic origin main "refs/tags/$TAG"
# Keep the unmodified signed feed as a release asset for recovery/republication.
gh release create "$TAG" --repo kokafang/Xingzhe --verify-tag --title "Xingzhe $VERSION" \
    --notes-file "updates/release-notes/$VERSION.html" \
    "$RELEASE_DIR/Xingzhe-$VERSION-macOS-arm64.zip" "$RELEASE_DIR/SHA256SUMS.txt" "$RELEASE_DIR/appcast.xml"
gh api "repos/kokafang/Xingzhe/releases/tags/$TAG" > "$RELEASE_DIR/published-release.json"
python3 - "$RELEASE_DIR" <<'PY'
import hashlib, json, pathlib, sys
folder = pathlib.Path(sys.argv[1])
release = json.loads((folder / 'published-release.json').read_text())
assert not release['draft'] and not release['prerelease']
assets = {a['name']: a for a in release['assets']}
for file in [next(folder.glob('*.zip')), folder / 'appcast.xml', folder / 'SHA256SUMS.txt']:
    asset = assets[file.name]
    assert asset['size'] == file.stat().st_size, file.name
    assert asset['digest'] == 'sha256:' + hashlib.sha256(file.read_bytes()).hexdigest(), file.name
print('PASS: published release assets match local signed artifacts')
PY
cp "$RELEASE_DIR/appcast.xml" updates/appcast.xml
git add updates/appcast.xml
git commit -m "Publish signed update feed for $VERSION"
git push origin main
printf 'Published: https://github.com/kokafang/Xingzhe/releases/tag/%s\n' "$TAG"
