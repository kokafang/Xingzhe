import Foundation
import ServiceManagement

// Refresh the running daemon for every build, including Developer ID builds
// whose designated signing requirement stays stable across app updates.
final class HelperRegistration {
    private let service = SMAppService.daemon(plistName: daemonPlist)
    private let probe = ServiceClient()
    private let defaults = UserDefaults.standard
    private let signatureKey = "registeredHelperAppSignature"
    private(set) var isRepairing = false
    var wasRegistered: Bool { defaults.string(forKey: signatureKey) != nil }

    private func registrationIdentity() throws -> String {
        let requirement = try signingRequirement(for: Bundle.main.bundleURL)
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return requirement + "|build=" + build
    }

    func markCurrent() {
        if let signature = try? registrationIdentity() {
            defaults.set(signature, forKey: signatureKey)
        }
    }

    func ensureCurrent(completion: @escaping (String?) -> Void) {
        guard service.status == .enabled else {
            completion(service.status == .requiresApproval ? "需批准后台服务 · 批准后再打开开关" : nil)
            return
        }
        do {
            let signature = try registrationIdentity()
            guard defaults.string(forKey: signatureKey) != signature else { completion(nil); return }
            isRepairing = true
            AwakeLog.app.notice("Refreshing helper after app update")
            service.unregister { [weak self] error in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if let error { self.finish(error.localizedDescription, completion); return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        do {
                            try self.service.register()
                            guard self.service.status == .enabled else {
                                self.finish("需批准后台服务 · 批准后再打开开关", completion)
                                return
                            }
                            self.probe.request("status") { _, message in
                                self.probe.disconnect()
                                if message.isEmpty { self.defaults.set(signature, forKey: self.signatureKey) }
                                self.finish(message.isEmpty ? nil : message, completion)
                            }
                        } catch { self.finish(error.localizedDescription, completion) }
                    }
                }
            }
        } catch { completion(error.localizedDescription) }
    }

    private func finish(_ error: String?, _ completion: (String?) -> Void) {
        isRepairing = false
        if let error { AwakeLog.app.error("Helper refresh failed: \(error, privacy: .public)") }
        else { AwakeLog.app.notice("Updated helper is ready") }
        completion(error)
    }
}
