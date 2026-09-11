import Foundation

enum ServiceTiming {
    static let heartbeatInterval: TimeInterval = 5
    // Leave recovery margin within the helper's 20-second lease, while allowing
    // a short scheduling delay without cancelling an otherwise healthy session.
    static let responseTimeout: TimeInterval = 12
    static let maximumSilence: TimeInterval = 18
    static let leaseDuration: TimeInterval = 20
}
