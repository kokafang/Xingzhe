import Foundation

// XPC replies arrive off the main queue. Claim completion there, so a reply
// already received cannot lose to a timeout waiting in the UI queue.
private final class ServiceReply {
    private let lock = NSLock()
    private var finished = false
    private let completion: (Bool, String) -> Void

    init(completion: @escaping (Bool, String) -> Void) { self.completion = completion }

    @discardableResult
    func resolve(_ active: Bool, _ message: String) -> Bool {
        lock.lock()
        guard !finished else { lock.unlock(); return false }
        finished = true
        lock.unlock()
        DispatchQueue.main.async { self.completion(active, message) }
        return true
    }
}

// The connection lifecycle is confined to the main queue.
final class ServiceClient {
    private var connection: NSXPCConnection?
    var onDisconnect: (() -> Void)?
    private let makeConnection: () throws -> NSXPCConnection

    init(makeConnection: @escaping () throws -> NSXPCConnection = ServiceClient.defaultConnection) {
        self.makeConnection = makeConnection
    }

    static func defaultConnection() throws -> NSXPCConnection {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Library/HelperTools/AwakeHelper")
        let connection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        connection.setCodeSigningRequirement(try signingRequirement(for: helper))
        return connection
    }

    private func connect() throws -> NSXPCConnection {
        if let connection { return connection }
        let connection = try makeConnection()
        connection.remoteObjectInterface = NSXPCInterface(with: AwakeService.self)
        connection.invalidationHandler = { [weak self, weak connection] in
            DispatchQueue.main.async {
                guard let self, let connection, self.connection === connection else { return }
                self.connection = nil
                AwakeLog.app.error("Helper connection invalidated")
                self.onDisconnect?()
            }
        }
        connection.interruptionHandler = { [weak connection] in connection?.invalidate() }
        self.connection = connection
        connection.resume()
        return connection
    }

    func request(_ action: String, enabled: Bool = false, completion: @escaping (Bool, String) -> Void) {
        let reply = ServiceReply(completion: completion)
        let started = ProcessInfo.processInfo.systemUptime
        let finish: (Bool, String) -> Void = { active, message in
            if reply.resolve(active, message) {
                let elapsed = ProcessInfo.processInfo.systemUptime - started
                if elapsed > 2 {
                    AwakeLog.app.notice("Delayed helper reply: action=\(action, privacy: .public), seconds=\(elapsed), active=\(active)")
                }
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
            DispatchQueue.main.asyncAfter(deadline: .now() + ServiceTiming.responseTimeout) { [weak self, weak connection] in
                guard reply.resolve(false, "后台服务响应超时，正在自动恢复原设置。") else { return }
                AwakeLog.app.error("Helper response timed out: action=\(action, privacy: .public)")
                if let connection, self?.connection === connection {
                    // Preserve this specific error instead of reporting a second,
                    // generic disconnect and discarding the request's completion.
                    self?.connection = nil
                    connection.invalidate()
                }
            }
        } catch { finish(false, error.localizedDescription) }
    }

    func disconnect() {
        let oldConnection = connection
        connection = nil
        oldConnection?.invalidate()
    }
}
