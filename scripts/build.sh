#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
APP="$PWD/build/醒着.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/HelperTools" "$APP/Contents/Library/LaunchDaemons" build/cache
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-swift-version 5 -sdk "$SDK" -target arm64-apple-macos13.0 -module-cache-path "$PWD/build/cache")
xcrun swiftc "${FLAGS[@]}" Sources/Shared/RecoveryEngine.swift Tests/main.swift -o build/RecoveryTests
build/RecoveryTests
xcrun swiftc "${FLAGS[@]}" Sources/Shared/*.swift Sources/Helper/main.swift -framework Foundation -framework Security -framework SystemConfiguration -o "$APP/Contents/Library/HelperTools/AwakeHelper"
xcrun swiftc "${FLAGS[@]}" Sources/Shared/*.swift Sources/App/*.swift -framework AppKit -framework ServiceManagement -framework Security -framework IOKit -o "$APP/Contents/MacOS/Awake"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/local.xingzhe.awake.helper.plist "$APP/Contents/Library/LaunchDaemons/"
codesign --force --sign - --identifier local.xingzhe.awake.helper "$APP/Contents/Library/HelperTools/AwakeHelper"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Library/LaunchDaemons/local.xingzhe.awake.helper.plist"
printf 'Built: %s\n' "$APP"
