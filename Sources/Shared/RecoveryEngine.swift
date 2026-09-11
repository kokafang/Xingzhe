import Foundation

protocol PowerBackend: AnyObject {
    func readDisabled() throws -> Bool
    func writeDisabled(_ value: Bool) throws
    func readJournal() throws -> Bool?
    func saveJournal(_ value: Bool) throws
    func clearJournal() throws
}

struct AwakeError: LocalizedError {
    let text: String
    var errorDescription: String? { text }
}

// Access only on the daemon's serial queue. The journal is the recovery source of truth.
final class RecoveryEngine {
    let backend: PowerBackend
    private(set) var owner: UUID?
    private var expiresAt: TimeInterval = 0
    private(set) var lastError = ""
    var active: Bool { owner != nil }

    init(backend: PowerBackend) { self.backend = backend }

    func recover() throws {
        owner = nil
        do {
            if let original = try backend.readJournal() {
                try backend.writeDisabled(original)
                guard try backend.readDisabled() == original else {
                    throw AwakeError(text: "系统未恢复休眠设置，将自动重试。")
                }
                try backend.clearJournal()
                AwakeLog.recovery.notice("Original SleepDisabled restored: \(original)")
            }
            lastError = ""
        } catch {
            lastError = error.localizedDescription
            AwakeLog.recovery.error("恢复失败，将重试：\(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func enable(owner requestedOwner: UUID, now: TimeInterval) throws {
        if let owner {
            guard owner == requestedOwner else { throw AwakeError(text: "另一个会话正在使用保持清醒。") }
            try renew(owner: requestedOwner, now: now)
            return
        }
        try recover()
        let original = try backend.readDisabled()
        try backend.saveJournal(original)
        do {
            try backend.writeDisabled(true)
            guard try backend.readDisabled() else { throw AwakeError(text: "系统未接受防休眠设置。") }
            owner = requestedOwner
            expiresAt = now + ServiceTiming.leaseDuration
            lastError = ""
        } catch {
            let failure = error
            do { try recover() } catch {
                throw AwakeError(text: "开启失败；恢复也未完成：\(error.localizedDescription)")
            }
            throw failure
        }
    }

    func renew(owner requestedOwner: UUID, now: TimeInterval) throws {
        guard owner == requestedOwner else { throw AwakeError(text: "保持清醒已结束，请重新打开开关。") }
        guard now < expiresAt else {
            try recover()
            throw AwakeError(text: "连接超时，已恢复原设置。")
        }
        do {
            if try !backend.readDisabled() {
                // Other power utilities may reset this global setting. While the
                // user's lease is valid, preserve their explicit enabled intent.
                // Do not replace the journal: it still holds the pre-enable value.
                try backend.writeDisabled(true)
                guard try backend.readDisabled() else {
                    throw AwakeError(text: "防休眠设置被其他程序更改，重新应用未成功。")
                }
                AwakeLog.recovery.notice("检测到外部电源设置重置，已重新应用保持清醒。")
            }
        } catch {
            let failure = error
            do { try recover() } catch {
                throw AwakeError(text: "保持清醒失败；恢复也未完成：\(error.localizedDescription)")
            }
            throw failure
        }
        expiresAt = now + ServiceTiming.leaseDuration
    }

    func disable(owner requestedOwner: UUID) throws {
        guard owner == nil || owner == requestedOwner else { throw AwakeError(text: "另一个会话正在使用保持清醒。") }
        try recover()
    }

    func disconnected(owner requestedOwner: UUID) {
        if owner == requestedOwner {
            AwakeLog.recovery.notice("Client disconnected; restoring original power settings")
            try? recover()
        }
    }

    func tick(now: TimeInterval) {
        if owner != nil && now >= expiresAt {
            AwakeLog.recovery.notice("Heartbeat lease expired; restoring original power settings")
        }
        if owner == nil || now >= expiresAt { try? recover() }
    }
}
