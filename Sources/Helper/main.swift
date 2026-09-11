import Foundation
import SystemConfiguration
import Darwin

final class SystemPowerBackend: PowerBackend {
    private let directory = URL(fileURLWithPath: "/var/db/local.xingzhe.awake", isDirectory: true)
    private var journal: URL { directory.appendingPathComponent("recovery.json") }

    private func pmset(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let watchdog = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 5, execute: watchdog)
        let hardStop = DispatchWorkItem { [weak process] in
            if let process, process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 6, execute: hardStop)
        defer { watchdog.cancel(); hardStop.cancel() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(decoding: data, as: UTF8.self)
        guard process.terminationStatus == 0 else {
            throw AwakeError(text: "电源设置失败：\(output.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        return output
    }

    func readDisabled() throws -> Bool {
        let output = try pmset(["-g"])
        for line in output.split(separator: "\n") {
            let fields = line.split(whereSeparator: { $0.isWhitespace })
            if fields.first == "SleepDisabled", fields.count == 2 {
                if fields[1] == "0" { return false }
                if fields[1] == "1" { return true }
            }
        }
        // Some versions omit the default false key; do not silently assume it.
        throw AwakeError(text: "无法确认系统休眠状态。")
    }

    func writeDisabled(_ value: Bool) throws { _ = try pmset(["-a", "disablesleep", value ? "1" : "0"]) }
    func readJournal() throws -> Bool? {
        guard FileManager.default.fileExists(atPath: journal.path) else { return nil }
        let data = try Data(contentsOf: journal)
        return try JSONDecoder().decode(Bool.self, from: data)
    }
    func saveJournal(_ value: Bool) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(value).write(to: journal, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journal.path)
        let fd = open(journal.path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { throw AwakeError(text: "无法保存恢复记录。") }
        defer { close(fd) }
        guard fsync(fd) == 0 else { throw AwakeError(text: "无法同步恢复记录。") }
    }
    func clearJournal() throws { try FileManager.default.removeItem(at: journal) }
}

let workQueue = DispatchQueue(label: "local.xingzhe.awake.power")
let engine = RecoveryEngine(backend: SystemPowerBackend())

final class Session: NSObject, AwakeService {
    let id = UUID()
    let uid: uid_t
    init(uid: uid_t) { self.uid = uid }

    func isConsoleUser() -> Bool {
        var current: uid_t = 0
        _ = SCDynamicStoreCopyConsoleUser(nil, &current, nil)
        return uid == current && uid != 0
    }

    func setEnabled(_ enabled: Bool, reply: @escaping (Bool, String) -> Void) {
        workQueue.async {
            do {
                if enabled {
                    guard self.isConsoleUser() else { throw AwakeError(text: "仅当前登录用户可以开启。") }
                    try engine.enable(owner: self.id, now: ProcessInfo.processInfo.systemUptime)
                } else { try engine.disable(owner: self.id) }
                reply(engine.owner == self.id, "")
            } catch { reply(engine.owner == self.id, error.localizedDescription) }
        }
    }
    func heartbeat(reply: @escaping (Bool, String) -> Void) {
        workQueue.async {
            do {
                guard self.isConsoleUser() else {
                    engine.disconnected(owner: self.id)
                    throw AwakeError(text: "用户会话已切换，已结束保持清醒。")
                }
                try engine.renew(owner: self.id, now: ProcessInfo.processInfo.systemUptime)
                reply(true, "")
            } catch {
                NSLog("保持清醒心跳结束：%@", error.localizedDescription)
                reply(false, error.localizedDescription)
            }
        }
    }
    func status(reply: @escaping (Bool, String) -> Void) {
        workQueue.async { reply(engine.owner == self.id, engine.lastError) }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard connection.effectiveUserIdentifier != 0 else { return false }
        let session = Session(uid: connection.effectiveUserIdentifier)
        connection.exportedInterface = NSXPCInterface(with: AwakeService.self)
        connection.exportedObject = session
        connection.invalidationHandler = { workQueue.async { engine.disconnected(owner: session.id) } }
        connection.interruptionHandler = { workQueue.async { engine.disconnected(owner: session.id) } }
        connection.resume()
        return true
    }
}

if CommandLine.arguments.contains("--diagnostics") {
    do {
        print("SleepDisabled=\(try SystemPowerBackend().readDisabled())")
        let containingApp = try containingAppURL()
        print("clientRequirement=\(try signingRequirement(for: containingApp))")
        exit(0)
    } catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
}

guard geteuid() == 0 else { fputs("后台服务需要系统授权。\n", stderr); exit(1) }
// Recover even if the containing application has since become invalid.
workQueue.sync { try? engine.recover() }
let timer = DispatchSource.makeTimerSource(queue: workQueue)
timer.schedule(deadline: .now() + 2, repeating: 2)
timer.setEventHandler { engine.tick(now: ProcessInfo.processInfo.systemUptime) }
timer.resume()

let listener = NSXPCListener(machServiceName: serviceName)
let delegate = ListenerDelegate()
do {
    listener.setConnectionCodeSigningRequirement(try signingRequirement(for: containingAppURL()))
    listener.delegate = delegate
    listener.resume()
} catch { NSLog("后台初始化失败：%@", error.localizedDescription) }
// Remain alive to retry restoration, even if authentication cannot initialize.
for sig in [SIGTERM, SIGINT] { signal(sig, SIG_IGN) }
let shutdown = DispatchSource.makeSignalSource(signal: SIGTERM, queue: workQueue)
shutdown.setEventHandler { try? engine.recover(); exit(0) }
shutdown.resume()
dispatchMain()
