import Foundation
import Observation

/// Where an external entry point (URL, complication, Control, Siri) wants the app to land.
enum LaunchAction: String, Sendable, Hashable {
    case listen
    case live

    /// `watchgpt://listen` or `watchgpt://live`.
    init?(url: URL) {
        guard url.scheme?.lowercased() == "watchgpt",
              let host = url.host()?.lowercased(),
              let action = LaunchAction(rawValue: host) else { return nil }
        self = action
    }

    var url: URL { URL(string: "watchgpt://\(rawValue)")! }
}

/// Mailbox between App Intents (which may run before any view exists) and the UI.
/// Compiled into the widget extension too, where it is inert: intents with
/// `openAppWhenRun` perform in the app process.
@MainActor @Observable
final class LaunchRouter {
    static let shared = LaunchRouter()

    private(set) var pending: LaunchAction?

    func request(_ action: LaunchAction) { pending = action }

    func take() -> LaunchAction? {
        defer { pending = nil }
        return pending
    }
}
