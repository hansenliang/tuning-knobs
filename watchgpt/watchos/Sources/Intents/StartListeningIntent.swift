import AppIntents

/// Opens the app already listening (A2). Used by the Control (Action button, D3), Siri, and Shortcuts.
///
/// Compiled into the app *and* the widget extension, because a Control's intent must exist in
/// both. With `openAppWhenRun`, the system runs `perform()` in the app process, where
/// LaunchRouter is live. The mic itself starts in the app, in the foreground.
struct StartListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask WatchGPT"
    static let description = IntentDescription("Opens WatchGPT already listening.")
    // Possibly deprecated in the watchOS 26 SDK in favor of `static var supportedModes: IntentModes { .foreground }`.
    // Either one works. Switch once it's confirmed on the SDK.
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.request(.listen)
        return .result()
    }
}
