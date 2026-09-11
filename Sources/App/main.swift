import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let toggle = NSSwitch()
    private let detail = NSTextField(wrappingLabelWithString: "已关闭 · 使用原有系统设置")
    private let client = ServiceClient()
    private let idle = IdleGuard()
    private let daemon = SMAppService.daemon(plistName: daemonPlist)
    private var enabled = false
    private var busy = false
    private var timer: Timer?
    private var waitingForApproval = false
    private var lastReply = Date.distantPast
    private var generation = 0
    private var lastDiagnostic = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier!)
        if others.count > 1 { NSApp.terminate(nil); return }
        buildMenu()
        client.onDisconnect = { [weak self] in
            guard let self else { return }
            self.generation += 1
            self.busy = false
            self.idle.stop()
            self.enabled = false
            self.render("连接已断开 · 后台将自动恢复原设置")
        }
        idle.onFailure = { [weak self] message in
            guard let self else { return }
            self.generation += 1
            self.busy = false
            self.client.disconnect()
            self.enabled = false
            self.render(message + " · 已结束保持清醒")
        }
        if !UserDefaults.standard.bool(forKey: "loginSetupCompleted") {
            do {
                try SMAppService.mainApp.register()
                UserDefaults.standard.set(true, forKey: "loginSetupCompleted")
            } catch { render("登录自启动未启用：\(error.localizedDescription)") }
        }
        timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 290, height: 90))
        let label = NSTextField(labelWithString: "保持清醒")
        label.font = .systemFont(ofSize: 14, weight: .medium)
        label.frame = NSRect(x: 18, y: 54, width: 180, height: 23)
        toggle.frame = NSRect(x: 230, y: 51, width: 44, height: 28)
        toggle.target = self; toggle.action = #selector(toggleChanged)
        toggle.setAccessibilityLabel("保持清醒")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.frame = NSRect(x: 18, y: 9, width: 254, height: 36)
        root.addSubview(label); root.addSubview(toggle); root.addSubview(detail)
        let controls = NSMenuItem(); controls.view = root
        menu.addItem(controls)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出醒着", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self; menu.addItem(quit)
        statusItem.menu = menu
        render()
    }

    private func render(_ message: String? = nil) {
        if let message, !message.isEmpty, message != lastDiagnostic {
            NSLog("醒着状态：%@", message)
        }
        lastDiagnostic = message ?? ""
        toggle.state = enabled ? .on : .off
        toggle.isEnabled = !busy
        statusItem.button?.image = NSImage(systemSymbolName: enabled ? "sun.max.fill" : "moon.zzz",
                                          accessibilityDescription: enabled ? "醒着：已开启" : "醒着：已关闭")
        statusItem.button?.image?.isTemplate = true
        statusItem.button?.toolTip = enabled ? "醒着 · 保持清醒已开启" : "醒着 · 已关闭"
        detail.stringValue = message ?? (enabled ? "已开启 · 保持运行，抑制自动锁屏" : "已关闭 · 使用原有系统设置")
    }

    @objc private func toggleChanged() {
        guard !busy else { return }
        if enabled { change(false); return }
        do {
            if daemon.status == .notRegistered || daemon.status == .notFound { try daemon.register() }
            if daemon.status == .requiresApproval {
                waitingForApproval = true
                render("需批准后台服务 · 批准后再打开开关")
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            guard daemon.status == .enabled else { throw AwakeError(text: "后台服务未启用，请在系统设置中批准。") }
            change(true)
        } catch { render(error.localizedDescription) }
    }

    private func change(_ desired: Bool) {
        generation += 1
        let current = generation
        busy = true
        render(desired ? "正在开启…" : "正在恢复原设置…")
        if desired {
            do { try idle.start() } catch { busy = false; render(error.localizedDescription); return }
        }
        client.request("set", enabled: desired) { [weak self] active, message in
            guard let self, self.generation == current else { return }
            self.busy = false; self.enabled = active; self.lastReply = Date()
            if !active { self.idle.stop() }
            self.render(message.isEmpty ? nil : message)
        }
    }

    private func tick() {
        if waitingForApproval && daemon.status == .enabled {
            waitingForApproval = false
            render("后台服务已就绪 · 可以打开开关")
        }
        guard enabled && !busy else { return }
        if Date().timeIntervalSince(lastReply) > 18 {
            idle.stop(); enabled = false; client.disconnect()
            render("连接超时 · 后台将自动恢复原设置")
            return
        }
        let current = generation
        client.request("heartbeat") { [weak self] active, message in
            guard let self, self.generation == current else { return }
            self.lastReply = Date(); self.enabled = active
            if !active { self.idle.stop() }
            self.render(message.isEmpty ? nil : message)
        }
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard statusItem != nil else { return .terminateNow }
        generation += 1
        idle.stop(); timer?.invalidate()
        if !enabled { client.disconnect(); return .terminateNow }
        client.request("set", enabled: false) { [weak self] _, message in
            self?.client.disconnect()
            if !message.isEmpty { NSLog("退出恢复：%@", message) }
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
