# Changelog

## 1.2.1

- Make “一直醒着” and “只醒一次” mutually exclusive, independently enabled modes; either switch starts its mode directly and both can be off.
- Turn the one-shot switch off after lid reopening; start both switches off after relaunch.
- Preserve the original power restoration record when switching between modes.

## 1.2.0

- Add a persistent opt-in “只醒一次” (Wake Once) switch. Each manual Keep Awake activation covers one lid close/open cycle; opening the lid restores the original power setting and turns Keep Awake off.
- Observe physical lid events independently of sleep, including transitions during helper startup; never enable automatically on subsequent lid closes.
- Stop a one-shot session safely if lid monitoring fails, and reject one-shot activation on machines without a readable lid sensor.
- Add close/open, cancellation, and delayed-enable regression coverage.

## 1.1.2

- Fall back to an explicit IOPMrootDomain SleepDisabled Boolean when pmset omits or cannot return the preference.
- Keep unknown state as an error; never assume missing values mean sleep is enabled.
- Add regression coverage for missing preferences, malformed output and fallback failures.

## 1.1.1

- Sign distribution builds with Developer ID, hardened runtime, and secure timestamps.
- Require Apple notarization and a stapled ticket before packaging releases.
- Refresh the privileged helper on build changes even when the signing identity is unchanged.

## 1.1.0

- Add in-app update checks, version display, and an optional daily automatic-check setting using Sparkle 2.9.6.
- Show release notes and download progress; install and restart only with user approval.
- Verify signed feeds and EdDSA update archives before extraction.
- Confirm power restoration before exiting for installation; refuse termination when recovery fails.
- Refresh the authenticated helper after an app signature change so the new app can connect after updating.
- Publish signed app-only ZIPs and an update feed after release assets are available.

## 1.0.2

- Use adaptive scheduling and a user-initiated power queue for the helper instead of a throttled background process.
- Tolerate a bounded delayed XPC reply, prevent overlapping heartbeats, and measure connection freshness with monotonic uptime.
- Claim replies before delivering them to the UI queue; ignore stale deadlines and late replies, and retain the specific timeout error.
- Keep the existing 20-second lease, disconnect restoration and recovery journal.
- Make app-owned status, timeout, slow-command and recovery events readable in system logs.
- Add real local-XPC regression checks for delayed replies, timeout, reconnection and late replies.

## 1.0.1

- Keep an active session enabled when another utility resets the sleep-prevention setting; reapply and verify the setting without replacing its recovery journal.
- Preserve timeout, disconnect, and failure recovery, with regression coverage.
- Record meaningful state changes and heartbeat failures in system logs.
- Add the supplied application icon while preserving the menu bar symbols.
- Publish the project as Xingzhe (醒着), with English and Chinese documentation, MIT-licensed source code, and a shareable macOS package.

## 1.0.0

- Initial native macOS menu bar utility with one Keep Awake switch.
- Add login startup, an authenticated privileged helper, temporary idle assertions, and journal-based recovery.
