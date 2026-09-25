import Foundation
import Network
import Observation

/// C3: audio turns that couldn't reach the gateway are kept on disk and retried. They're never lost to a dead zone.
///
/// Retry triggers, from most to least reliable on a real watch:
///  1. A backoff timer (15 s, doubling to 5 min) while items exist.
///  2. The app becoming active, and "Retry now" (both call `retryAll()` through AppState).
///  3. NWPathMonitor reporting `.satisfied`. This is only a hint: TN3135 says that outside an
///     audio session it can stay `.unsatisfied` on watchOS even while URLSession works. So we
///     never use `.unsatisfied` to skip an attempt.
@MainActor @Observable
final class OfflineQueue {
    struct Item: Codable, Identifiable, Sendable {
        let id: UUID
        let createdAt: Date
        let conversationID: String?
        let reply: String
        let model: String
    }

    enum Delivery: Sendable {
        case delivered    // the server accepted it (turn.started). Remove.
        case retryLater   // still offline or busy. Keep.
        case drop         // permanently rejected (e.g. 413, 402). Remove.
    }

    private(set) var items: [Item] = []
    private(set) var isRetrying = false

    /// Wired by AppState to the turn pipeline.
    @ObservationIgnored var deliver: ((Item, URL) async -> Delivery)?

    private let directory: URL
    private let monitor = NWPathMonitor()
    @ObservationIgnored private var backoffTask: Task<Void, Never>?
    @ObservationIgnored private var backoff: Duration = .seconds(15)
    private static let maxBackoff: Duration = .seconds(300)

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = support.appending(path: "OfflineTurns", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        items = Self.loadItems(in: directory)
        startPathMonitor()
        if !items.isEmpty { scheduleBackoffRetry() }
    }

    /// Moves the recording into the queue directory, so the caller's temp file is gone afterwards.
    func enqueue(recording: URL, conversationID: String?, reply: ReplyMode, model: ModelChoice) throws {
        let item = Item(id: UUID(), createdAt: .now, conversationID: conversationID,
                        reply: reply.rawValue, model: model.rawValue)
        try FileManager.default.moveItem(at: recording, to: audioURL(for: item))
        try JSONEncoder().encode(item).write(to: metadataURL(for: item), options: .atomic)
        items.append(item)
        backoff = .seconds(15)
        scheduleBackoffRetry()
    }

    /// Sends oldest first and stops at the first item that still can't go.
    func retryAll() async {
        guard !isRetrying, !items.isEmpty, let deliver else { return }
        isRetrying = true
        defer { isRetrying = false }

        for item in items {
            switch await deliver(item, audioURL(for: item)) {
            case .delivered, .drop:
                remove(item)
            case .retryLater:
                scheduleBackoffRetry()
                return
            }
        }
        backoffTask?.cancel()
        backoffTask = nil
        backoff = .seconds(15)
    }

    // MARK: - Private

    private func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: audioURL(for: item))
        try? FileManager.default.removeItem(at: metadataURL(for: item))
        items.removeAll { $0.id == item.id }
    }

    private func scheduleBackoffRetry() {
        backoffTask?.cancel()
        let delay = backoff
        backoff = min(backoff * 2, Self.maxBackoff)
        backoffTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.retryAll()
        }
    }

    private func startPathMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in await self?.retryAll() }
        }
        monitor.start(queue: DispatchQueue(label: "app.watchgpt.offline.path"))
    }

    private func audioURL(for item: Item) -> URL {
        directory.appending(path: "\(item.id.uuidString).m4a")
    }

    private func metadataURL(for item: Item) -> URL {
        directory.appending(path: "\(item.id.uuidString).json")
    }

    private static func loadItems(in directory: URL) -> [Item] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Item? in
                guard let data = try? Data(contentsOf: url),
                      let item = try? JSONDecoder().decode(Item.self, from: data) else { return nil }
                let audio = directory.appending(path: "\(item.id.uuidString).m4a")
                return FileManager.default.fileExists(atPath: audio.path()) ? item : nil
            }
            .sorted { $0.createdAt < $1.createdAt }
    }
}
