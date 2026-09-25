import AppIntents

/// Opens the app straight into a Live conversation (B1).
struct StartLiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Start WatchGPT Live"
    static let description = IntentDescription("Opens WatchGPT in a hands-free Live conversation.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        LaunchRouter.shared.request(.live)
        return .result()
    }
}
