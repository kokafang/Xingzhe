import Foundation

func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    precondition(condition(), message)
    print("PASS \(message)")
}
var pending: ((Bool, String) -> Void)?
var calls = 0
let gate = UpdatePreparation { reply in calls += 1; pending = reply }
var results: [Bool] = []
gate.run { allowed, _ in results.append(allowed) }
check(results.isEmpty, "installation waits for confirmed restoration")
gate.run { allowed, _ in results.append(allowed) }
check(calls == 1, "concurrent requests share one restoration")
let first = pending!
first(false, "")
check(results == [true, true], "confirmed inactive state allows installation")
first(true, "late")
check(results.count == 2, "duplicate restoration replies are ignored")
gate.run { allowed, _ in results.append(allowed) }
first(false, "")
check(results.count == 2, "old reply cannot complete a new attempt")
pending!(false, "恢复失败")
check(results.last == false, "inactive state with a recovery error blocks installation")
gate.run { allowed, _ in results.append(allowed) }
pending!(true, "")
check(results.last == false, "still-active helper blocks installation")
gate.run { allowed, _ in results.append(allowed) }
pending!(false, "")
check(results.last == true && calls == 4, "successful retry can proceed after a failure")
