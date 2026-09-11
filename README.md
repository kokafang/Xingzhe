<p align="center"><img src="Resources/AppIcon.png" width="96" alt="Xingzhe app icon"></p>

# Xingzhe · 醒着

Keep your Mac awake with one menu bar switch.

Xingzhe is a small native macOS utility built with Swift and AppKit. It lives in the menu bar, with no regular window or Dock icon.

[简体中文](README.zh-CN.md) · [Download](https://github.com/kokafang/Xingzhe/releases/latest) · [Report an issue](https://github.com/kokafang/Xingzhe/issues)

## Requirements

- Apple silicon Mac (M series), macOS 13 or later.
- Approval for the bundled background service on first use.
- The downloadable build is locally signed with an ad-hoc signature and **is not Apple-notarized**. It is a testing build; macOS may block the first launch. Intel Macs and Windows are not supported by this build.

## Install

1. Download the ZIP from [Releases](https://github.com/kokafang/Xingzhe/releases/latest) and extract it.
2. Move **醒着.app** to **Applications**, then open it.
3. Click the moon icon in the menu bar and turn on **保持清醒** (Keep Awake).
4. If macOS requests approval, allow Xingzhe / 醒着 under **System Settings → General → Login Items & Extensions**, then turn on the switch again. On some macOS versions, the page is called **Login Items**.

If the first launch is blocked because the developer cannot be verified, follow [Apple’s instructions for opening an app you trust](https://support.apple.com/en-us/102445). No system-wide security changes are required.

The sun icon means Keep Awake is enabled; the moon means it is disabled. The app requests login startup on its first launch, but **Keep Awake starts off each time the app launches**. Turn it off and quit the app before removing it.

## Updates

Click **检查更新…** (Check for Updates) in the menu bar menu. You can also enable **自动检查更新** for daily checks. Xingzhe asks before enabling automatic checks and before installing; automatic downloads and silent installation are disabled.

The updater shows release notes and progress, verifies the signed feed and archive, then installs and restarts. Before quitting, Xingzhe confirms that the helper restored the original power setting. Failed restoration pauses installation. After restart, Keep Awake is off and the helper is refreshed automatically if the app signature changed. macOS may still request background-service approval.

Versions 1.0.2 and older need one manual upgrade to 1.1.0. Later upgrades can be installed from within the app.

## What it does

- Prevents system sleep while Keep Awake is enabled and uses temporary IOKit assertions to keep the display active and suppress idle locking.
- Reapplies the sleep-prevention setting if another utility resets it during an active session, then verifies the setting.
- Restores the setting captured before enabling when you turn it off, quit, disconnect, or stop sending heartbeats for 20 seconds.
- Persists a recovery journal so the background service can restore settings after a crash; failed restoration is retried.
- Leaves password settings untouched and does not unlock a manually locked screen.

Lid-closed behavior must be tested on the target Mac, on battery and on AC power. Reading back the power setting is not a substitute for that test. Managed-device policies may limit idle-lock suppression. Recovery cannot run while the background service is forcibly stopped or removed.

## Build and test

Use an Apple silicon Mac with Xcode and its command-line tools installed:

```sh
git clone https://github.com/kokafang/Xingzhe.git
cd Xingzhe
bash scripts/build.sh
python3 scripts/test-launch-path.py
```

The app is generated at `build/醒着.app`. The build runs recovery and local-XPC timeout tests, compiles the app and helper, signs them locally, and validates the signatures and property lists. Sparkle 2.9.6 is bundled for signed updates; its official distribution is downloaded and checksum-verified by the build script.

Create a shareable ZIP with the app, documentation, license notices, and a SHA-256 checksum:

```sh
bash scripts/package-release.sh
```

Output: `build/releases/1.1.0/Xingzhe-1.1.0-macOS-arm64.zip` and `build/releases/1.1.0/SHA256SUMS.txt`. Release signing requires the maintainer’s Sparkle signing key in the login Keychain.

## How it works

The AppKit menu bar app communicates with an authenticated privileged helper over NSXPC. The helper is registered with `SMAppService` and runs fixed `pmset` operations; it does not accept arbitrary commands or file paths. Both ends validate code signatures.

Before changing `SleepDisabled`, the helper stores the original value in a recovery journal. A session sends a heartbeat every five seconds, with at most one heartbeat in flight. The helper uses adaptive scheduling; replies may take up to 12 seconds before the client ends the session, while the helper retains its 20-second lease. The helper restores the original value when that session ends or expires. Temporary display and user-activity assertions live in the app process.

| Directory | Purpose |
| --- | --- |
| `Sources/App` | Menu bar UI, service client, temporary idle assertions |
| `Sources/Helper` | Privileged service and system power backend |
| `Sources/Shared` | Recovery engine, XPC protocol, signature verification |
| `Tests` | Recovery and failure-path tests |
| `Resources` | App icon and application/service configuration |
| `scripts` | Build, packaging, and launch-path regression checks |

## License

The source code is licensed under the [MIT License](LICENSE). The supplied application artwork is excluded from that license; see [NOTICE](NOTICE).

## Maintainer release workflow

The original project's EdDSA key lives in the maintainer's login Keychain under the Sparkle account `local.xingzhe.awake`. Never commit or upload a private key. For a fork, generate your own key with `build/dependencies/Sparkle-2.9.6/bin/generate_keys --account YOUR_ACCOUNT` and change the feed URL, public key and signing account in the scripts.

Increment both version fields in `Resources/Info.plist`, add `updates/release-notes/VERSION.html`, update the changelog, and commit/merge the reviewed changes to `main`. Run `bash scripts/publish-release.sh`. It builds, signs and verifies the update, publishes immutable release assets, verifies their hashes, and only then commits the signed feed. A failed publication must not be repaired by editing signed XML or overwriting an existing ZIP; restore the matching signed feed asset or publish a new version.

Run `python3 scripts/test-updates.py` on the signing Mac for isolated end-to-end Sparkle tests. Test applications do not register the production helper or change power settings. See [third-party notices](THIRD_PARTY_NOTICES.md).
