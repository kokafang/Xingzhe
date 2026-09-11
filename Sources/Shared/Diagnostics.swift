import os

// Log only app-owned state and errors; never enable system-wide private logging.
enum AwakeLog {
    static let app = Logger(subsystem: "local.xingzhe.awake", category: "app")
    static let helper = Logger(subsystem: "local.xingzhe.awake", category: "helper")
    static let recovery = Logger(subsystem: "local.xingzhe.awake", category: "recovery")
}
