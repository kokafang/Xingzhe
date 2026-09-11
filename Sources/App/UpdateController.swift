import AppKit
import Sparkle

final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, NSMenuItemValidation {
    private lazy var controller = SPUStandardUpdaterController(startingUpdater: false,
        updaterDelegate: self, userDriverDelegate: self)
    private weak var checkItem: NSMenuItem?
    private(set) var installingUpdate = false
    var canStartCheck: () -> Bool = { true }

    func appendMenuItems(to menu: NSMenu) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let label = NSMenuItem(title: "醒着 \(version)", action: nil, keyEquivalent: "")
        label.isEnabled = false
        menu.addItem(label)
        let check = NSMenuItem(title: "检查更新…", action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
        check.target = controller
        checkItem = check
        menu.addItem(check)
        let automatic = NSMenuItem(title: "自动检查更新", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        automatic.target = self
        menu.addItem(automatic)
        menu.addItem(.separator())
    }

    func start() { controller.startUpdater() }

    @objc private func toggleAutomaticChecks() {
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        return true
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { true }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard canStartCheck() else { throw AwakeError(text: "正在处理保持清醒，请稍后检查更新。") }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installingUpdate = true
        AwakeLog.app.notice("Preparing update to \(item.displayVersionString, privacy: .public)")
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installingUpdate = false
        AwakeLog.app.error("Update ended: \(error.localizedDescription, privacy: .public)")
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }
    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool { true }
    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        checkItem?.title = "发现新版本 \(update.displayVersionString)…"
    }
    func standardUserDriverWillFinishUpdateSession() { checkItem?.title = "检查更新…" }

    func showRecoveryFailure(_ message: String, forUpdate: Bool) {
        let alert = NSAlert()
        alert.messageText = forUpdate ? "更新已暂停" : "退出已暂停"
        alert.informativeText = "尚未确认恢复原电源设置，应用没有退出。\n\n\(message)\n\n请稍后重试。"
        alert.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}
