import Foundation
import WidgetKit

/// Small App Group store the Smart Stack widget reads ("Last: garlic shrimp in 15 min").
enum SharedStore {
    static let appGroup = "group.app.watchgpt"
    private static let textKey = "lastAnswer.text"
    private static let dateKey = "lastAnswer.at"

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func saveLastAnswer(_ text: String, at date: Date) {
        defaults.set(String(text.prefix(120)), forKey: textKey)
        defaults.set(date, forKey: dateKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func lastAnswer() -> (text: String, at: Date)? {
        guard let text = defaults.string(forKey: textKey),
              let date = defaults.object(forKey: dateKey) as? Date else { return nil }
        return (text, date)
    }
}
