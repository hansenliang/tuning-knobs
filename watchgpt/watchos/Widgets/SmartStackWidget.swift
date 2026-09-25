import SwiftUI
import WidgetKit

/// D2: Smart Stack card. "WatchGPT · Tap to ask · Last: …"
/// TODO: add watchOS 26 relevance (RelevanceConfiguration) so it rises at commute or workout end.
struct SmartStackWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.watchgpt.smartstack", provider: LastAnswerProvider()) { entry in
            SmartStackView(entry: entry)
        }
        .configurationDisplayName("WatchGPT")
        .description("Tap to ask. Shows your last answer.")
        .supportedFamilies([.accessoryRectangular])
    }
}

private struct SmartStackView: View {
    let entry: LastAnswerEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label("WatchGPT", systemImage: "mic.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.amber)
                .widgetAccentable()
            Text("Tap to ask")
                .font(.system(size: 15, weight: .semibold))
            if let last = entry.lastAnswer {
                Text("Last: \(last)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(LaunchAction.listen.url)
        .containerBackground(Theme.card, for: .widget)
    }
}
