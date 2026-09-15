#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/fetch-sparkle.sh
SPARKLE="$PWD/build/dependencies/Sparkle-2.9.6"
APP="$PWD/build/醒着.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/HelperTools" "$APP/Contents/Library/LaunchDaemons" build/cache
SDK="$(xcrun --sdk macosx --show-sdk-path)"
FLAGS=(-swift-version 5 -sdk "$SDK" -target arm64-apple-macos13.0 -module-cache-path "$PWD/build/cache")
xcrun swiftc "${FLAGS[@]}" Sources/Shared/RecoveryEngine.swift Sources/Shared/Diagnostics.swift Sources/Shared/ServiceTiming.swift Tests/main.swift -o build/RecoveryTests
build/RecoveryTests
xcrun swiftc "${FLAGS[@]}" Sources/Shared/RecoveryEngine.swift Sources/Shared/Diagnostics.swift Sources/Shared/ServiceTiming.swift Sources/Shared/SleepStateReader.swift Tests/PowerState/main.swift -o build/PowerStateTests
build/PowerStateTests
xcrun swiftc "${FLAGS[@]}" Sources/Shared/*.swift Sources/App/ServiceClient.swift Tests/ServiceClient/main.swift -framework Security -o build/ServiceClientTests
build/ServiceClientTests
xcrun swiftc "${FLAGS[@]}" Sources/Shared/UpdatePreparation.swift Tests/Updates/main.swift -o build/UpdateTests
build/UpdateTests
xcrun swiftc "${FLAGS[@]}" Sources/Shared/*.swift Sources/Helper/main.swift -framework Foundation -framework Security -framework SystemConfiguration -o "$APP/Contents/Library/HelperTools/AwakeHelper"
xcrun swiftc "${FLAGS[@]}" Sources/Shared/*.swift Sources/App/*.swift -framework AppKit -framework ServiceManagement -framework Security -framework IOKit -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -o "$APP/Contents/MacOS/Awake"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp "$SPARKLE/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp README.md README.zh-CN.md LICENSE NOTICE CHANGELOG.md THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/local.xingzhe.awake.helper.plist "$APP/Contents/Library/LaunchDaemons/"
if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
    bash scripts/sign-app.sh "$APP"
else
    codesign --force --sign - --identifier local.xingzhe.awake.helper "$APP/Contents/Library/HelperTools/AwakeHelper"
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist" "$APP/Contents/Library/LaunchDaemons/local.xingzhe.awake.helper.plist"
printf 'Built: %s\n' "$APP"
