// The preference is stored by the UI. This state belongs only to one manually
// requested awake session, including time spent waiting for the helper.
struct WakeOnceSession {
    enum Phase: Equatable { case inactive, waitingForClose, waitingForOpen, stopRequested }
    private(set) var phase: Phase = .inactive
    var needsStop: Bool { phase == .stopRequested }
    var isTracking: Bool { phase == .waitingForClose || phase == .waitingForOpen }

    mutating func begin(lidClosed: Bool) {
        phase = lidClosed ? .waitingForOpen : .waitingForClose
    }

    @discardableResult
    mutating func observe(lidClosed: Bool) -> Bool {
        switch (phase, lidClosed) {
        case (.waitingForClose, true): phase = .waitingForOpen
        case (.waitingForOpen, false): return requestStop()
        default: break
        }
        return false
    }

    @discardableResult
    mutating func requestStop() -> Bool {
        guard isTracking else { return false }
        phase = .stopRequested
        return true
    }

    mutating func cancel() { phase = .inactive }
}
