import SwiftUI
import WidgetKit

struct LastAnswerEntry: TimelineEntry {
    let date: Date
    let lastAnswer: String?
}

/// Reads the App Group snapshot the app writes after each answer. The app reloads timelines,
/// so there's no schedule here.
struct LastAnswerProvider: TimelineProvider {
    func placeholder(in context: Context) -> LastAnswerEntry {
        LastAnswerEntry(date: .now, lastAnswer: "Garlic shrimp in 15 min")
    }

    func getSnapshot(in context: Context, completion: @escaping (LastAnswerEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LastAnswerEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .never))
    }

    private func current() -> LastAnswerEntry {
        LastAnswerEntry(date: .now, lastAnswer: SharedStore.lastAnswer()?.text)
    }
}
