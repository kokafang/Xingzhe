import Foundation
import IOKit.pwr_mgt

final class IdleGuard {
    private var displayID: IOPMAssertionID = 0
    private var activityID: IOPMAssertionID = 0
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    var onFailure: ((String) -> Void)?

    func start() throws {
        guard timer == nil else { return }
        let result = IOPMAssertionCreateWithName(kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn), "醒着：保持清醒" as CFString, &displayID)
        guard result == kIOReturnSuccess else { throw AwakeError(text: "无法启用防自动锁屏。") }
        do { try pulse() } catch { stop(); throw error }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                                                        reason: "醒着：保持后台服务连接")
        timer = Timer(timeInterval: 10, repeats: true) { [weak self] _ in
            guard let self else { return }
            do { try self.pulse() } catch {
                self.stop()
                self.onFailure?(error.localizedDescription)
            }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func pulse() throws {
        let result = IOPMAssertionDeclareUserActivity("醒着：用户保持清醒" as CFString,
                                                     kIOPMUserActiveLocal, &activityID)
        guard result == kIOReturnSuccess else { throw AwakeError(text: "无法声明用户活跃状态。") }
    }
    func stop() {
        timer?.invalidate(); timer = nil
        if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
        if displayID != 0 { IOPMAssertionRelease(displayID); displayID = 0 }
        if activityID != 0 { IOPMAssertionRelease(activityID); activityID = 0 }
    }
    deinit { stop() }
}
