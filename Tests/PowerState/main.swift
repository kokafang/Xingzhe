import Foundation
import CoreFoundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ name: String) {
    guard condition() else { fatalError(name) }
    checks += 1
    print("PASS: \(name)")
}
check(SleepStateReader.parse("System-wide power settings:\n SleepDisabled\t0\nCurrently in use:") == false, "explicit off")
check(SleepStateReader.parse(" SleepDisabled 1") == true, "explicit on")
check(SleepStateReader.parse("\tSleepDisabled\t 1\r\n") == true, "whitespace")
for output in ["", "Currently in use:\n sleep 1", "SleepDisabled yes", "SleepDisabled 1 extra", "SleepDisabled 0\nSleepDisabled 1"] {
    check(SleepStateReader.parse(output) == nil, "missing or malformed text rejected")
}
for state in [false, true] {
    let value = try SleepStateReader.read(pmsetOutput: { "Currently in use:\n sleep 1" }, kernelValue: { state ? kCFBooleanTrue : kCFBooleanFalse })
    check(value == state, "missing preference uses explicit kernel Boolean \(state)")
}
let preferred = try SleepStateReader.read(pmsetOutput: { "SleepDisabled 1" }, kernelValue: { fatalError("unneeded fallback") })
check(preferred, "valid preference preserves original state")
for invalid: CFTypeRef? in [nil, "0" as CFString, NSNumber(value: 0), NSNumber(value: 1)] {
    do {
        _ = try SleepStateReader.read(pmsetOutput: { "" }, kernelValue: { invalid })
        fatalError("unknown must not become false")
    } catch { check(true, "unknown kernel value fails closed") }
}
let recovered = try SleepStateReader.read(pmsetOutput: { throw NSError(domain: "test", code: 1) }, kernelValue: { kCFBooleanFalse })
check(!recovered, "command failure can use explicit kernel state")
do {
    _ = try SleepStateReader.read(pmsetOutput: { throw NSError(domain: "test", code: 1) }, kernelValue: { nil })
    fatalError("both reads failed")
} catch { check(true, "both failures stay errors") }
print("\(checks) power-state checks passed")
