import Foundation
import Security
import MachO

func signingRequirement(for url: URL) throws -> String {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
        throw AwakeError(text: "无法读取程序签名。")
    }
    guard SecStaticCodeCheckValidity(code, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess else {
        throw AwakeError(text: "程序签名校验失败，请重新安装。")
    }
    var requirement: SecRequirement?
    guard SecCodeCopyDesignatedRequirement(code, [], &requirement) == errSecSuccess, let requirement else {
        throw AwakeError(text: "无法读取签名要求。")
    }
    var string: CFString?
    guard SecRequirementCopyString(requirement, [], &string) == errSecSuccess, let string else {
        throw AwakeError(text: "无法读取签名标识。")
    }
    return string as String
}

// launchd may provide a relative argv[0]; dyld knows the loaded executable path.
func loadedExecutableURL() throws -> URL {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else {
        throw AwakeError(text: "无法确定后台程序位置。")
    }
    return URL(fileURLWithPath: String(cString: buffer)).resolvingSymlinksInPath()
}
func containingAppURL() throws -> URL {
    try loadedExecutableURL().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
}
