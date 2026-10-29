import Foundation
import IOKit
import IOKit.pwr_mgt

// Main-thread only. Monitor physical lid state independently of system sleep:
// Keep Awake can suppress sleep while clamshell notifications still arrive.
final class LidMonitor {
    var onChange: ((Bool) -> Void)?
    var onFailure: ((String) -> Void)?

    // IOPM.h's kIOPMMessageClamshellStateChange is a C macro Swift cannot
    // import: iokit_family_msg(sub_iokit_powermanagement, 0x100).
    private static let clamshellStateChange: UInt32 = (0x38 << 26) | (13 << 14) | 0x100

    private var root: io_service_t = IO_OBJECT_NULL
    private var notification: io_object_t = IO_OBJECT_NULL
    private var port: IONotificationPortRef?
    private var source: CFRunLoopSource?
    private var pollTimer: Timer?
    private var monitoring = false
    private var lastClosed: Bool?

    // Register first, then sample the initial state. The run-loop source is
    // attached last, so this method never calls either client closure inline.
    func start() throws -> Bool {
        precondition(Thread.isMainThread)
        stop()
        guard let matching = IOServiceMatching("IOPMrootDomain") else {
            throw AwakeError(text: "无法检测合盖状态，不能启用只醒一次。")
        }
        root = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard root != IO_OBJECT_NULL,
              let newPort = IONotificationPortCreate(kIOMainPortDefault) else {
            stop()
            throw AwakeError(text: "无法检测合盖状态，不能启用只醒一次。")
        }
        port = newPort
        let result = IOServiceAddInterestNotification(
            newPort, root, kIOGeneralInterest,
            { context, _, messageType, argument in
                guard messageType == LidMonitor.clamshellStateChange,
                      let context else { return }
                let monitor = Unmanaged<LidMonitor>.fromOpaque(context).takeUnretainedValue()
                // The argument is a bitfield cast to a pointer, not a pointer
                // to dereference. nil is a valid open-lid event (all bits 0).
                let closed = UInt(bitPattern: argument) & UInt(kClamshellStateBit) != 0
                monitor.receive(closed)
            }, Unmanaged.passUnretained(self).toOpaque(), &notification)
        guard result == KERN_SUCCESS,
              let initialClosed = readClosed(),
              let newSource = IONotificationPortGetRunLoopSource(newPort)?.takeUnretainedValue() else {
            stop()
            throw AwakeError(text: "这台电脑暂不支持可靠的合盖检测。")
        }
        lastClosed = initialClosed
        source = newSource
        monitoring = true
        CFRunLoopAddSource(CFRunLoopGetMain(), newSource, .commonModes)
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            self?.poll()
        }
        timer.tolerance = 0.2
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
        return initialClosed
    }

    func stop() {
        precondition(Thread.isMainThread)
        monitoring = false
        lastClosed = nil
        pollTimer?.invalidate()
        pollTimer = nil
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        source = nil
        if notification != IO_OBJECT_NULL {
            IOObjectRelease(notification)
            notification = IO_OBJECT_NULL
        }
        if let port { IONotificationPortDestroy(port) }
        port = nil
        if root != IO_OBJECT_NULL {
            IOObjectRelease(root)
            root = IO_OBJECT_NULL
        }
    }

    private func readClosed() -> Bool? {
        guard root != IO_OBJECT_NULL,
              let value = IORegistryEntryCreateCFProperty(
                root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
              CFGetTypeID(value) == CFBooleanGetTypeID() else { return nil }
        return CFEqual(value, kCFBooleanTrue)
    }

    private func receive(_ closed: Bool) {
        precondition(Thread.isMainThread)
        guard monitoring, lastClosed != closed else { return }
        lastClosed = closed
        onChange?(closed)
    }

    private func poll() {
        guard monitoring else { return }
        guard let closed = readClosed() else {
            // Stop before reporting failure: repeated polling cannot report the
            // same failure or claim an unknown value means the lid is open.
            stop()
            onFailure?("合盖检测已失效，正在结束本次保持清醒。")
            return
        }
        receive(closed)
    }

    deinit { stop() }
}
