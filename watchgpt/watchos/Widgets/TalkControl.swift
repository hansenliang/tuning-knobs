import AppIntents
import SwiftUI
import WidgetKit

/// D3: a watchOS 26 Control. It can go in Control Center or the Smart Stack, and on Ultra it can be
/// bound to the Action button. The press runs StartListeningIntent, which opens the app into Listening.
struct TalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.watchgpt.control.talk") {
            ControlWidgetButton(action: StartListeningIntent()) {
                Label("Ask", systemImage: "mic.fill")
            }
        }
        .displayName("Ask WatchGPT")
        .description("Opens WatchGPT already listening.")
    }
}
