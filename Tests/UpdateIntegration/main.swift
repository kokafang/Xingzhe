import AppKit
import Sparkle

// This executable is bundled only by scripts/test-updates.py in isolated test
// apps. It never registers a helper or touches actual system power settings.
func record(_ event: String) {
    let path = Bundle.main.object(forInfoDictionaryKey: "TestResultPath") as! String
    let url = URL(fileURLWithPath: path)
    if !FileManager.default.fileExists(atPath: path) { FileManager.default.createFile(atPath: path, contents: nil) }
    let file = try! FileHandle(forWritingTo: url)
    try! file.seekToEnd()
    try! file.write(contentsOf: Data((event + "\n").utf8))
    try! file.close()
}
func finish(_ event: String) {
    record(event)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { exit(0) }
}
final class Driver: NSObject, SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { record("checking") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        record("found:" + appcastItem.versionString)
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {}
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); finish("no-update") }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { acknowledgement(); finish("error:" + error.localizedDescription) }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { record("downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { record("extracting") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { record("ready"); reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { record("installing") }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
}
final class Delegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    let driver = Driver()
    var updater: SPUUpdater!
    let preparation = UpdatePreparation { reply in record("restored"); reply(false, "") }
    func applicationDidFinishLaunching(_ notification: Notification) {
        record("launched:" + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String))
        if Bundle.main.object(forInfoDictionaryKey: "TestCompleteOnLaunch") as? Bool == true { finish("updated"); return }
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        do { try updater.start() } catch { finish("error:" + error.localizedDescription); return }
        updater.checkForUpdates()
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        preparation.run { allowed, _ in
            DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: allowed) }
        }
        return .terminateLater
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) { finish("error:" + error.localizedDescription) }
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let delegate = Delegate()
app.delegate = delegate
app.run()
