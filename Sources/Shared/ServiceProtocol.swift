import Foundation

let serviceName = "local.xingzhe.awake.helper"
let daemonPlist = serviceName + ".plist"

@objc protocol AwakeService {
    func setEnabled(_ enabled: Bool, reply: @escaping (Bool, String) -> Void)
    func heartbeat(reply: @escaping (Bool, String) -> Void)
    func status(reply: @escaping (Bool, String) -> Void)
}
