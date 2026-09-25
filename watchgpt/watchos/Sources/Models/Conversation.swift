import Foundation

struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    enum Role: String, Codable, Sendable { case user, assistant }
    enum Source: String, Codable, Sendable { case turn, live }

    let id: UUID
    let role: Role
    var text: String
    let at: Date
    let source: Source
}

/// The one thread the watch shows. Push-to-talk turns and Live transcripts share it
/// (B4: "Saved to your thread"), and so does the server-side `conversation_id`.
struct Conversation: Codable, Equatable, Sendable {
    static let maxMessages = 20                        // the server keeps 20 as well
    static let staleAfter: TimeInterval = 6 * 60 * 60  // start fresh after a long gap
    private static let storageKey = "conversation.v1"

    var id: String?
    private(set) var messages: [ChatMessage] = []

    @discardableResult
    mutating func append(_ role: ChatMessage.Role, text: String, source: ChatMessage.Source = .turn) -> UUID {
        let message = ChatMessage(id: UUID(), role: role, text: text, at: .now, source: source)
        messages.append(message)
        if messages.count > Self.maxMessages {
            messages.removeFirst(messages.count - Self.maxMessages)
        }
        return message.id
    }

    func message(_ id: UUID) -> ChatMessage? { messages.first { $0.id == id } }

    mutating func setText(_ text: String, for id: UUID) {
        if let i = index(of: id) { messages[i].text = text }
    }

    mutating func appendText(_ delta: String, to id: UUID) {
        if let i = index(of: id) { messages[i].text += delta }
    }

    mutating func remove(_ id: UUID) {
        messages.removeAll { $0.id == id }
    }

    private func index(of id: UUID) -> Int? { messages.firstIndex { $0.id == id } }

    // MARK: Persistence (UserDefaults; the thread is tiny)

    static func loadSaved() -> Conversation {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode(Conversation.self, from: data) else { return Conversation() }
        if let last = saved.messages.last, Date.now.timeIntervalSince(last.at) > staleAfter {
            return Conversation()
        }
        return saved
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
