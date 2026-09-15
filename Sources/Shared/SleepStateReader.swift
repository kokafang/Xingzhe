import Foundation
import CoreFoundation

// pmset omits SleepDisabled when the stored preference is absent. Only an
// explicit IOPMrootDomain Boolean is accepted as an alternate state source.
enum SleepStateReader {
    static func parse(_ output: String) -> Bool? {
        let rows = output.split(separator: "\n").map { $0.split(whereSeparator: { $0.isWhitespace }) }
            .filter { $0.first == "SleepDisabled" }
        guard rows.count == 1, rows[0].count == 2 else { return nil }
        switch rows[0][1] {
        case "0": return false
        case "1": return true
        default: return nil
        }
    }

    static func read(pmsetOutput: () throws -> String, kernelValue: () -> CFTypeRef?) throws -> Bool {
        if let output = try? pmsetOutput(), let value = parse(output) { return value }
        if let value = kernelValue(), CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFEqual(value, kCFBooleanTrue)
        }
        throw AwakeError(text: "无法确认系统休眠状态：电源设置和内核状态均读取失败。请反馈系统版本。")
    }
}
