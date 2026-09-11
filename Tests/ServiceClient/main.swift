import Foundation

final class DelayedService: NSObject, AwakeService {
    private let lock = NSLock()
    private var delay: TimeInterval = 8.5
    func configure(delay: TimeInterval) { lock.lock(); self.delay = delay; lock.unlock() }
    func setEnabled(_ enabled: Bool, reply: @escaping (Bool, String) -> Void) { reply(enabled, "") }
    func status(reply: @escaping (Bool, String) -> Void) { reply(false, "") }
    func heartbeat(reply: @escaping (Bool, String) -> Void) {
        lock.lock(); let delay = self.delay; lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { reply(true, "") }
    }
}
final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = DelayedService()
    private let lock = NSLock()
    private var connections: [NSXPCConnection] = []
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: AwakeService.self)
        connection.exportedObject = service
        lock.lock(); connections.append(connection); lock.unlock()
        connection.resume()
        return true
    }
    func close() {
        lock.lock(); let old = connections; connections = []; lock.unlock()
        old.forEach { $0.invalidate() }
    }
}
func require(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fputs("FAIL: \(message)\n", stderr); exit(1) }
}
func wait(seconds: TimeInterval, until done: () -> Bool) {
    let end = ProcessInfo.processInfo.systemUptime + seconds
    while !done() && ProcessInfo.processInfo.systemUptime < end {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }
}
let delegate = ListenerDelegate()
let listener = NSXPCListener.anonymous()
listener.delegate = delegate
listener.resume()
var connectionCount = 0
let client = ServiceClient {
    connectionCount += 1
    return NSXPCConnection(listenerEndpoint: listener.endpoint)
}
var disconnectCount = 0
client.onDisconnect = { disconnectCount += 1 }
var delayedReply: (Bool, String)?
client.request("heartbeat") { delayedReply = ($0, $1) }
wait(seconds: 14) { delayedReply != nil }
require(delayedReply?.0 == true && delayedReply?.1 == "", "healthy reply after 8.5 seconds must survive")
require(disconnectCount == 0 && connectionCount == 1, "healthy delay must keep the same connection")
print("PASS: healthy 8.5-second heartbeat delay keeps the connection")

// The completed first request's old deadline fires during this request. It must
// neither cancel the connection nor interfere with this request's own deadline.
delegate.service.configure(delay: 13.5)
var timeoutReply: (Bool, String)?
var completionCount = 0
let started = ProcessInfo.processInfo.systemUptime
client.request("heartbeat") { active, message in
    completionCount += 1
    timeoutReply = (active, message)
}
wait(seconds: 13) { timeoutReply != nil }
let elapsed = ProcessInfo.processInfo.systemUptime - started
require(timeoutReply?.0 == false && timeoutReply?.1.contains("响应超时") == true, "missing reply must report the specific timeout")
require(elapsed >= 11.5 && elapsed < 13, "only the current request's deadline may end it")
require(disconnectCount == 0, "timeout must not be overwritten by generic disconnect")
print("PASS: missing reply times out once, at its own bounded deadline")

// Reconnect immediately, before the old server's delayed reply arrives.
var statusReply: (Bool, String)?
client.request("status") { statusReply = ($0, $1) }
wait(seconds: 2) { statusReply != nil }
require(statusReply?.0 == false && statusReply?.1 == "" && connectionCount == 2, "request after timeout must create a working new connection")
wait(seconds: 2) { false }
require(completionCount == 1 && timeoutReply?.0 == false, "late success must never revive a timed-out request")
require(disconnectCount == 0, "old connection must not invalidate replacement connection")
print("PASS: late reply cannot revive a timed-out request or cancel a new connection")
client.disconnect()
wait(seconds: 0.1) { false }
require(disconnectCount == 0, "intentional disconnect must not invoke onDisconnect")
listener.invalidate()
delegate.close()
print("4 service-client checks passed")
