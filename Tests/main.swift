import Foundation

final class Fake: PowerBackend {
    var disabled = false
    var journal: Bool?
    var failWrite = false
    var failSave = false
    var failClear = false
    var ignoreEnableWrite = false
    var writes: [Bool] = []
    func readDisabled() throws -> Bool { disabled }
    func writeDisabled(_ value: Bool) throws {
        if failWrite { throw AwakeError(text: "write failed") }
        writes.append(value)
        if !(ignoreEnableWrite && value) { disabled = value }
    }
    func readJournal() throws -> Bool? { journal }
    func saveJournal(_ value: Bool) throws {
        if failSave { throw AwakeError(text: "save failed") }; journal = value
    }
    func clearJournal() throws {
        if failClear { throw AwakeError(text: "clear failed") }; journal = nil
    }
}
var count = 0
func test(_ name: String, _ body: () throws -> Void) {
    do { try body(); count += 1; print("PASS \(name)") }
    catch { fatalError("FAIL \(name): \(error)") }
}
func expect(_ value: @autoclosure () -> Bool) { precondition(value()) }
func throwsError(_ body: () throws -> Void) { do { try body(); fatalError("Expected error") } catch {} }

test("normal off restores initial false") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); expect(b.disabled && b.journal == false)
    try e.disable(owner: id); expect(!b.disabled && b.journal == nil && !e.active)
}
test("preserves original disabled true") {
    let b = Fake(); b.disabled = true; let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); try e.disable(owner: id); expect(b.disabled && b.journal == nil)
}
test("journal failure cannot mutate power") {
    let b = Fake(); b.failSave = true; let e = RecoveryEngine(backend: b)
    throwsError { try e.enable(owner: UUID(), now: 0) }; expect(b.writes.isEmpty && !e.active)
}
test("failed write keeps recovery journal and retries") {
    let b = Fake(); b.failWrite = true; let e = RecoveryEngine(backend: b)
    throwsError { try e.enable(owner: UUID(), now: 0) }; expect(b.journal == false && !e.active)
    b.failWrite = false; e.tick(now: 1); expect(b.journal == nil && !b.disabled)
}
test("crash restart restores before next enable") {
    let b = Fake(); b.disabled = true; b.journal = false
    let e = RecoveryEngine(backend: b); try e.recover(); expect(!b.disabled && b.journal == nil)
}
test("expiry recovers; heartbeat extends lease") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); try e.renew(owner: id, now: 15)
    e.tick(now: 21); expect(e.active); e.tick(now: 35); expect(!e.active && !b.disabled)
}
test("late heartbeat cannot revive expired lease") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0)
    throwsError { try e.renew(owner: id, now: 20) }; expect(!e.active && !b.disabled)
}
test("different session cannot turn off or renew") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0)
    throwsError { try e.disable(owner: UUID()) }; throwsError { try e.renew(owner: UUID(), now: 1) }
    expect(e.active); e.disconnected(owner: UUID()); expect(e.active)
    e.disconnected(owner: id); expect(!e.active && !b.disabled)
}
test("failed recovery never clears journal") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.failWrite = true
    throwsError { try e.disable(owner: id) }; expect(b.journal == false && !e.lastError.isEmpty)
    b.failWrite = false; e.tick(now: 1); expect(b.journal == nil && e.lastError.isEmpty)
}
test("external reset is repaired without ending the active session") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.disabled = false
    try e.renew(owner: id, now: 15)
    expect(e.owner == id && b.disabled && b.journal == false)
    e.tick(now: 21); expect(e.active)
    try e.disable(owner: id); expect(!b.disabled && b.journal == nil)
}
test("repeated external resets preserve the original recovery value") {
    let b = Fake(); b.disabled = true; let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0)
    for now in [5.0, 10.0, 15.0] {
        b.disabled = false; try e.renew(owner: id, now: now)
        expect(e.active && b.disabled && b.journal == true)
    }
    e.disconnected(owner: id); expect(!e.active && b.disabled && b.journal == nil)
}
test("expired session cannot reapply sleep prevention") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.disabled = false; b.writes = []
    throwsError { try e.renew(owner: id, now: 20) }
    expect(!e.active && !b.disabled && !b.writes.contains(true))
}
test("another session cannot reapply sleep prevention") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.disabled = false; b.writes = []
    throwsError { try e.renew(owner: UUID(), now: 5) }
    expect(e.owner == id && !b.disabled && b.writes.isEmpty)
}
test("failed reapplication ends the session and retains recovery for retry") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.disabled = false; b.failWrite = true
    throwsError { try e.renew(owner: id, now: 5) }
    expect(!e.active && b.journal == false && !e.lastError.isEmpty)
    b.failWrite = false; e.tick(now: 6)
    expect(!b.disabled && b.journal == nil && e.lastError.isEmpty)
}
test("unverified reapplication cannot report success") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.disabled = false; b.ignoreEnableWrite = true
    throwsError { try e.renew(owner: id, now: 5) }
    expect(!e.active && !b.disabled && b.journal == nil)
}
test("unchanged settings require no extra writes") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.writes = []
    try e.renew(owner: id, now: 5)
    expect(e.active && b.writes.isEmpty && b.journal == false)
}
test("journal clear failure is retried safely") {
    let b = Fake(); let e = RecoveryEngine(backend: b); let id = UUID()
    try e.enable(owner: id, now: 0); b.failClear = true
    throwsError { try e.disable(owner: id) }; expect(!b.disabled && b.journal == false)
    b.failClear = false; e.tick(now: 1); expect(b.journal == nil)
}
print("\(count) recovery tests passed")
