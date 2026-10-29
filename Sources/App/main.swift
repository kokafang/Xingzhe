import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let toggle = NSSwitch()
    private let onceToggle = NSSwitch()
    private let lidMonitor = LidMonitor()
    private var onceSession = WakeOnceSession()
    private var automaticStopMessage: String?
    // Session mode, not a persisted preference: launch always starts with both off.
    private var onlyOnce = false
    private let detail = NSTextField(wrappingLabelWithString: "已关闭 · 使用原有系统设置")
    private let client = ServiceClient()
    private let idle = IdleGuard()
    private let registration = HelperRegistration()
    private let updates = UpdateController()
    private lazy var updatePreparation = UpdatePreparation { [weak self] reply in
        guard let self else { reply(true, "应用已退出。"); return }
        if self.daemon.status == .notRegistered || self.daemon.status == .notFound {
            reply(false, self.registration.wasRegistered ? "请先重新启用后台服务，再重试更新。" : "")
        } else if self.daemon.status == .enabled {
            self.client.request("set", enabled: false, completion: reply)
        } else {
            reply(true, "请先在系统设置中批准后台服务，再重试更新。")
        }
    }
    private let daemon = SMAppService.daemon(plistName: daemonPlist)
    private var enabled = false
    private var busy = false
    private var timer: Timer?
    private var waitingForApproval = false
    private var lastReply: TimeInterval = 0
    private var heartbeatPending = false
    private var generation = 0
    private var lastDiagnostic = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if others.count > 1 { NSApp.terminate(nil); return }
        buildMenu()
        lidMonitor.onChange = { [weak self] closed in
            guard let self else { return }
            if self.onceSession.observe(lidClosed: closed) {
                self.requestAutomaticStop("已开盖 · 醒着已自动关闭")
            }
        }
        lidMonitor.onFailure = { [weak self] message in
            guard let self, self.onceSession.requestStop() else { return }
            self.requestAutomaticStop(message + " · 已结束本次醒着")
        }
        client.onDisconnect = { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.busy = false
            self.heartbeatPending = false
            self.idle.stop()
            self.cancelOnceTracking()
            self.enabled = false
            self.render("连接已断开 · 后台将自动恢复原设置")
        }
        idle.onFailure = { [weak self] message in
            guard let self else { return }
            self.generation += 1
            self.busy = false
            self.heartbeatPending = false
            self.client.disconnect()
            self.cancelOnceTracking()
            self.enabled = false
            self.render(message + " · 已结束保持清醒")
        }
        if !UserDefaults.standard.bool(forKey: "loginSetupCompleted") {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "loginSetupCompleted")
            } catch { render("登录自启动未启用：\(error.localizedDescription)") }
        }
        timer = Timer(timeInterval: ServiceTiming.heartbeatInterval, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        updates.canStartCheck = { [weak self] in self?.busy == false }
        busy = true
        render("正在检查后台服务…")
        registration.ensureCurrent { [weak self] error in
            guard let self else { return }
            self.busy = false
            self.waitingForApproval = self.daemon.status == .requiresApproval
            self.render(error)
            self.updates.start()
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 132))
        let label = NSTextField(labelWithString: "一直醒着")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 18, y: 96, width: 180, height: 23)
        toggle.frame = NSRect(x: 230, y: 93, width: 44, height: 28)
        toggle.target = self; toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("一直醒着")
        toggle.toolTip = "保持运行，直到手动关闭。与只醒一次互斥。"
        let onceLabel = NSTextField(labelWithString: "只醒一次")
        onceLabel.font = .systemFont(ofSize: 14, weight: .medium)
        onceLabel.frame = NSRect(x: 18, y: 58, width: 180, height: 23)
        onceToggle.frame = NSRect(x: 230, y: 55, width: 44, height: 28)
        onceToggle.target = self; onceToggle.action = #selector(onceChanged)
        onceToggle.setAccessibilityLabel("只醒一次，合盖后再次开盖自动关闭醒着")
        onceToggle.toolTip = "开启即保持运行；合盖后再次开盖自动关闭。与一直醒着互斥。"
        root.addSubview(onceLabel); root.addSubview(onceToggle)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 18, y: 9, width: 254, height: 36)
        root.addSubview(label); root.addSubview(toggle); root.addSubview(detail)
        let controls = NSMenuItem(); controls.view = root
        menu.addItem(controls)
        menu.addItem(.separator())
        updates.appendMenuItems(to: menu)
        let quit = NSMenuItem(title: "退出醒着", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        render()
    }

    private func render(_ message: String? = nil) {
        if let message, !message.isEmpty, message != lastDiagnostic {
            AwakeLog.app.notice("状态：\(message, privacy: .public)")
        }
        lastDiagnostic = message ?? ""
        toggle.state = enabled && !onlyOnce ? .on : .off
        toggle.isEnabled = !busy
        onceToggle.state = enabled && onlyOnce ? .on : .off
        onceToggle.isEnabled = !busy
        statusItem.button?.image = NSImage(systemSymbolName: enabled ? "sun.max.fill" : "moon.zzz",
                                          accessibilityDescription: enabled ? "醒着：已开启" : "醒着：已关闭")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = enabled ? "醒着 · 保持清醒已开启" : "醒着 · 已关闭"
        let standard = enabled ? "一直醒着 · 手动关闭后恢复原设置" : "已关闭 · 使用原有系统设置"
        let onceHint = "只醒一次 · 合盖后开盖自动关闭"
        detail.stringValue = message ?? (enabled && onlyOnce ? onceHint : standard)
    }

    @objc private func onceChanged() {
        guard !busy else { return }
        if onceToggle.state == .on { enableMode(once: true) }
        else { change(false) }
    }

    private func beginOnceTracking() throws {
        cancelOnceTracking()
        onceSession.begin(lidClosed: try lidMonitor.start())
    }

    private func cancelOnceTracking() {
        lidMonitor.stop()
        onceSession.cancel()
        automaticStopMessage = nil
    }

    private func requestAutomaticStop(_ confirmation: String) {
        automaticStopMessage = confirmation
        lidMonitor.stop()
        idle.stop()
        // Registration and enable requests must finish before set(false), so a
        // delayed enable cannot turn the session on again after lid opening.
        if busy { render("本次醒着已结束 · 等待后台确认关闭…") }
        else if enabled { change(false, confirmation: confirmation) }
    }

    @objc private func toggleChanged() {
        guard !busy else { return }
        if toggle.state == .on { enableMode(once: false) }
        else { change(false) }
    }

    private func enableMode(once: Bool) {
        if enabled {
            // Change only the ending condition; keep the same helper session and
            // original recovery journal while moving between the two modes.
            guard onlyOnce != once else { render(); return }
            if once {
                do { try beginOnceTracking() }
                catch { render(error.localizedDescription); return }
            } else { cancelOnceTracking() }
            onlyOnce = once
            render()
            return
        }
        onlyOnce = once
        do {
            if daemon.status == .notRegistered || daemon.status == .notFound { try daemon.register() }
            if daemon.status == .requiresApproval {
                waitingForApproval = true
                render("需批准后台服务 · 批准后再打开开关")
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            guard daemon.status == .enabled else { throw AwakeError(text: "后台服务未启用，请在系统设置中批准。") }
            if onlyOnce { try beginOnceTracking() }
            busy = true
            render("正在检查后台服务…")
            registration.ensureCurrent { [weak self] error in
                guard let self else { return }
                self.busy = false
                if let error {
                    self.cancelOnceTracking()
                    self.waitingForApproval = self.daemon.status == .requiresApproval
                    self.render(error)
                } else if self.onceSession.needsStop {
                    let message = self.automaticStopMessage
                    self.cancelOnceTracking()
                    self.render(message)
                } else { self.change(true) }
            }
        } catch { cancelOnceTracking(); render(error.localizedDescription) }
    }

    private func change(_ desired: Bool, confirmation: String? = nil) {
        if !desired { cancelOnceTracking(); idle.stop() }
        generation += 1
        let current = generation
        busy = true
        heartbeatPending = false
        render(desired ? "正在开启…" : "正在恢复原设置…")
        if desired {
            do { try idle.start() } catch { busy = false; cancelOnceTracking(); render(error.localizedDescription); return }
        }
        client.request("set", enabled: desired) { [weak self] active, message in
            guard let self, self.generation == current else { return }
            self.busy = false; self.enabled = active; self.lastReply = ProcessInfo.processInfo.systemUptime
            if desired && self.onceSession.needsStop {
                let reason = self.automaticStopMessage
                if active { self.change(false, confirmation: reason) }
                else {
                    self.idle.stop(); self.cancelOnceTracking()
                    self.render(message.isEmpty ? reason : message)
                }
                return
            }
            if !active { self.idle.stop(); self.cancelOnceTracking() }
            if !desired && active {
                self.enabled = false
                self.client.disconnect()
                self.render("关闭尚未确认 · 后台将按超时恢复原设置")
                return
            }
            if active && message.isEmpty { self.registration.markCurrent() }
            self.render(message.isEmpty ? confirmation : message)
        }
    }

    private func tick() {
        if waitingForApproval && daemon.status == .enabled {
            waitingForApproval = false
            render("后台服务已就绪 · 可以打开开关")
        }
        guard enabled && !busy else { return }
        if ProcessInfo.processInfo.systemUptime - lastReply > ServiceTiming.maximumSilence {
            generation += 1; heartbeatPending = false
            idle.stop(); cancelOnceTracking(); enabled = false; client.disconnect()
            render("连接超时 · 后台将自动恢复原设置")
            return
        }
        guard !heartbeatPending else { return }
        heartbeatPending = true
        let current = generation
        client.request("heartbeat") { [weak self] active, message in
            guard let self, self.generation == current else { return }
            self.heartbeatPending = false
            self.lastReply = ProcessInfo.processInfo.systemUptime; self.enabled = active
            if !active { self.idle.stop(); self.cancelOnceTracking() }
            self.render(message.isEmpty ? nil : message)
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard statusItem != nil else { return .terminateNow }
        guard !registration.isRepairing else { return .terminateCancel }
        cancelOnceTracking()
        if updates.installingUpdate || daemon.status == .enabled {
            generation += 1
            busy = true; heartbeatPending = false
            idle.stop(); enabled = false
            render(updates.installingUpdate ? "更新前正在恢复原设置…" : "正在恢复原设置…")
            updatePreparation.run { [weak self] allowed, message in
                // A never-registered helper can reply synchronously. Reply to
                // AppKit only after this method has returned terminateLater.
                DispatchQueue.main.async {
                    guard let self else { NSApp.reply(toApplicationShouldTerminate: false); return }
                    self.client.disconnect()
                    self.busy = false
                    if allowed { self.timer?.invalidate() }
                    else { self.render("恢复尚未完成 · 已暂停退出") }
                    NSApp.reply(toApplicationShouldTerminate: allowed)
                    if !allowed { self.updates.showRecoveryFailure(message, forUpdate: self.updates.installingUpdate) }
                }
            }
            return .terminateLater
        }
        generation += 1
        idle.stop(); timer?.invalidate()
        if !enabled { client.disconnect(); return .terminateNow }
        client.request("set", enabled: false) { [weak self] _, message in
            self?.client.disconnect()
            if !message.isEmpty { AwakeLog.app.error("退出恢复：\(message, privacy: .public)") }
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

if CommandLine.arguments.contains("--repair-helper") {
    let service = SMAppService.daemon(plistName: daemonPlist)
    if service.status == .notRegistered || service.status == .notFound {
        do { try service.register(); print("helper=\(service.status.rawValue)"); exit(service.status == .enabled ? 0 : 1) }
        catch { print("register failed: \(error.localizedDescription)"); exit(1) }
    }
    var done = false
    service.unregister { error in
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            do {
                if let error { print("unregister: \(error.localizedDescription)") }
                try service.register()
                print("helper=\(service.status.rawValue)")
            } catch { print("repair failed: \(error.localizedDescription)") }
            done = true
        }
    }
    let deadline = Date().addingTimeInterval(15)
    while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    exit(done && service.status == .enabled ? 0 : 1)
}
if CommandLine.arguments.contains("--check-service") || CommandLine.arguments.contains("--test-service") || CommandLine.arguments.contains("--test-disconnect") {
    let client = ServiceClient()
    let idle = IdleGuard()
    var done = false
    var success = false
    let test = !CommandLine.arguments.contains("--check-service")
    client.request(test ? "set" : "status", enabled: test) { active, message in
        print("initial active=\(active), error=\(message)")
        if !message.isEmpty || (test && !active) { done = true; return }
        if !test { success = true; done = true; return }
        if CommandLine.arguments.contains("--test-disconnect") { exit(0) }
        do { try idle.start() } catch { print(error); client.disconnect(); done = true; return }
        let read = Process(); read.executableURL = URL(fileURLWithPath: "/usr/bin/pmset"); read.arguments = ["-g"]
        try? read.run(); read.waitUntilExit()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            client.request("heartbeat") { alive, error in
                print("heartbeat active=\(alive), error=\(error)")
                client.request("set", enabled: false) { active, message in
                    print("restored active=\(active), error=\(message)")
                    idle.stop(); success = alive && error.isEmpty && !active && message.isEmpty; done = true
                }
            }
        }
    }
    let deadline = Date().addingTimeInterval(25)
    while !done && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.1)) }
    idle.stop(); client.disconnect()
    exit(success ? 0 : 1)
}

if CommandLine.arguments.contains("--diagnostics") {
    print("login=\(SMAppService.mainApp.status.rawValue)")
    print("helper=\(SMAppService.daemon(plistName: daemonPlist).status.rawValue)")
    print("appSignature=\((try? signingRequirement(for: Bundle.main.bundleURL)) ?? "invalid")")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
