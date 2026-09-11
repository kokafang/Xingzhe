import Foundation

// Main-thread gate shared by update termination and its tests. No installer may
// proceed based only on the UI switch; the helper must confirm recovery.
final class UpdatePreparation {
    typealias Reply = (Bool, String) -> Void
    private let restore: (@escaping Reply) -> Void
    private var attempt: UUID?
    private var waiting: [Reply] = []

    init(restore: @escaping (@escaping Reply) -> Void) { self.restore = restore }

    func run(completion: @escaping Reply) {
        waiting.append(completion)
        guard attempt == nil else { return }
        let token = UUID()
        attempt = token
        restore { [weak self] active, message in
            guard let self, self.attempt == token else { return }
            self.attempt = nil
            let callbacks = self.waiting
            self.waiting = []
            let allowed = !active && message.isEmpty
            let error = allowed ? "" : (message.isEmpty ? "后台仍在保持清醒，请稍后重试更新。" : message)
            callbacks.forEach { $0(allowed, error) }
        }
    }
}
