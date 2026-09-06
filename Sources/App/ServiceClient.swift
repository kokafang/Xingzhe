import Foundation

final class ServiceClient {
    private var connection: NSXPCConnection?
    var onDisconnect: (() -> Void)?

    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/AwakeHelper")
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.setCodeSigningRequirement(try signingRequirement(for: helper))
        connection.remoteObjectInterface = NSXPCInterface(with: AwakeService.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, self.connection === connection else { return }
                self.connection = nil
                self.onDisconnect?()
            }
        }
        connection.interruptionHandler = { [weak connection] in connection?.invalidate() }
        self.connection = connection
        connection.resume()
        return connection
    }

    func request(_ action: String, enabled: Bool = false, completion: @escaping (Bool, String) -> Void) {
        var finished = false
        let finish: (Bool, String) -> Void = { active, message in
            DispatchQueue.main.async {
                guard !finished else { return }; finished = true
                completion(active, message)
            }
        }
        do {
            let connection = try connect()
            guard let remote = connection.remoteObjectProxyWithErrorHandler({ error in
                finish(false, "后台服务尚未连接：\(error.localizedDescription)")
            }) as? AwakeService else { throw AwakeError(text: "后台服务无法连接。") }
            switch action {
            case "set": remote.setEnabled(enabled, reply: finish)
            case "heartbeat": remote.heartbeat(reply: finish)
            default: remote.status(reply: finish)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak connection] in
                if !finished {
                    connection?.invalidate()
                    finish(false, "后台服务响应超时，正在自动恢复原设置。")
                }
            }
        } catch { finish(false, error.localizedDescription) }
    }
    func disconnect() { connection?.invalidate(); connection = nil }
}
