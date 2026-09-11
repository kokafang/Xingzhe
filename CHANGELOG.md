# Changelog

## 1.0.1

- Keep an active session enabled when another utility resets the sleep-prevention setting; reapply and verify the setting without replacing its recovery journal.
- Preserve timeout, disconnect, and failure recovery, with regression coverage.
- Record meaningful state changes and heartbeat failures in system logs.
- Add the supplied application icon while preserving the menu bar symbols.
- Publish the project as Xingzhe (醒着), with English and Chinese documentation, MIT-licensed source code, and a shareable macOS package.

## 1.0.0

- Initial native macOS menu bar utility with one Keep Awake switch.
- Add login startup, an authenticated privileged helper, temporary idle assertions, and journal-based recovery.
