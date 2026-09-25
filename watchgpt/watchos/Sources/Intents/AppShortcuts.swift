import AppIntents

/// Siri phrases, and Action button → Shortcut binding. App target only (excluded from the widget extension).
struct WatchGPTShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartListeningIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Talk to \(.applicationName)",
                "Open \(.applicationName) listening",
            ],
            shortTitle: "Ask",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StartLiveIntent(),
            phrases: [
                "Start \(.applicationName) Live",
                "Go live with \(.applicationName)",
            ],
            shortTitle: "Live",
            systemImageName: "waveform"
        )
    }
}
