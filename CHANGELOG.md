# Changelog

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
