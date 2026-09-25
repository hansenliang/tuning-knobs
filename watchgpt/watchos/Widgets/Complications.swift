import SwiftUI
import WidgetKit

/// D1: circular complication with an amber ring. One tap opens straight into Listening.
struct AskComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.watchgpt.complication.ask", provider: LastAnswerProvider()) { _ in
            ComplicationView(symbol: "mic.fill", label: "Ask", action: .listen, ringColor: Theme.amber)
        }
        .configurationDisplayName("Ask")
        .description("Opens WatchGPT already listening.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

/// D1, second slot: starts Live.
struct LiveComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.watchgpt.complication.live", provider: LastAnswerProvider()) { _ in
            ComplicationView(symbol: "waveform", label: "Live", action: .live, ringColor: Color(hex: 0x444444))
        }
        .configurationDisplayName("Live")
        .description("Starts a hands-free Live conversation.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

private struct ComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let symbol: String
    let label: String
    let action: LaunchAction
    let ringColor: Color

    var body: some View {
        content
            .widgetURL(action.url)
            .containerBackground(Color.clear, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.amber)
                .widgetAccentable()
                .widgetLabel(label)
        case .accessoryInline:
            Label("\(label) · WatchGPT", systemImage: symbol)
        default:
            ZStack {
                AccessoryWidgetBackground()
                Circle().strokeBorder(ringColor, lineWidth: 2)
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(action == .listen ? Theme.amber : Theme.dim)
                    .widgetAccentable()
            }
        }
    }
}
