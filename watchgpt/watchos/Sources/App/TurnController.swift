import Foundation
import Observation

/// The push-to-talk / typed turn pipeline (A3/A4): streams `POST /v1/turns`, builds the
/// thread as events arrive, and feeds `audio.segment`s to the SegmentPlayer.
/// Mirrors `ask()` in server/public/index.html.
@MainActor @Observable
final class TurnController {
    enum Status: Equatable {
        case idle, sending, thinking, streaming, done, queuedOffline
        case failed(String)
    }

    enum Outcome {
        case completed
        case cancelled(accepted: Bool)
        case failed(APIError?)
    }

    private(set) var conversation = Conversation.loadSaved()
    private(set) var status: Status = .idle
    /// The assistant message currently receiving `text.delta`s (drawn with a cursor).
    private(set) var streamingMessageID: UUID?
    var model: ModelChoice = .fast

    @ObservationIgnored var onPaywall: ((Date?) -> Void)?
    @ObservationIgnored var onQueuedOffline: (() -> Void)?
    /// A turn finished or was cancelled. AppState may release the audio session.
    @ObservationIgnored var onIdle: (() -> Void)?

    private let api: APIClient
    private let player: SegmentPlayer
    private let offline: OfflineQueue
    @ObservationIgnored private var task: Task<Outcome, Never>?
    /// Each turn gets a token, so a cancelled turn that's still unwinding can't touch the next one.
    @ObservationIgnored private var turnToken = UUID()

    init(api: APIClient, player: SegmentPlayer, offline: OfflineQueue) {
        self.api = api
        self.player = player
        self.offline = offline
    }

    // MARK: Derived UI state

    var isBusy: Bool { status == .sending || status == .thinking || status == .streaming }
    var isAwaitingReply: Bool { status == .sending || status == .thinking }
    var recentMessages: [ChatMessage] { Array(conversation.messages.suffix(8)) }
    var lastAnswer: ChatMessage? { conversation.messages.last { $0.role == .assistant && !$0.text.isEmpty } }
    /// Changes whenever the thread grows. AnswerView scrolls on it.
    var scrollKey: Int { conversation.messages.count &* 100_000 &+ (conversation.messages.last?.text.count ?? 0) }

    // MARK: Turns

    func ask(text: String, reply: ReplyMode) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let token = beginTurn()
        let userID = conversation.append(.user, text: trimmed)
        let stream = api.streamTurn(text: trimmed, conversationID: conversation.id, reply: reply, model: model)
        task = Task {
            let outcome = await run(stream, reply: reply, userMessageID: userID, token: token)
            onIdle?()
            return outcome
        }
    }

    /// A fresh recording. If we're offline, it moves to the OfflineQueue (C3). Otherwise the file is deleted.
    func ask(audioFile: URL, reply: ReplyMode = .voice) {
        let token = beginTurn()
        let userID = conversation.append(.user, text: "")   // filled in by the `transcript` event
        let conversationID = conversation.id
        let model = self.model
        let stream = api.streamTurn(audioFile: audioFile, conversationID: conversationID, reply: reply, model: model)
        task = Task {
            let outcome = await run(stream, reply: reply, userMessageID: userID, token: token)
            if case .failed(.offline?) = outcome {
                do {
                    try offline.enqueue(recording: audioFile, conversationID: conversationID, reply: reply, model: model)
                    if token == turnToken {
                        status = .queuedOffline
                        onQueuedOffline?()
                    }
                } catch {
                    Log.turn.error("Couldn't queue recording: \(error.localizedDescription)")
                    status = .failed("Couldn't save your question.")
                }
            } else {
                try? FileManager.default.removeItem(at: audioFile)
            }
            onIdle?()
            return outcome
        }
    }

    /// OfflineQueue retry. `onAccepted` runs when the server starts the turn, so the UI can show it.
    func deliver(queued item: OfflineQueue.Item, audioFile: URL,
                 onAccepted: @escaping () -> Void) async -> OfflineQueue.Delivery {
        guard !isBusy else { return .retryLater }
        let reply = ReplyMode(rawValue: item.reply) ?? .voice
        let model = ModelChoice(rawValue: item.model) ?? .fast
        let token = beginTurn()
        let userID = conversation.append(.user, text: "")
        let stream = api.streamTurn(audioFile: audioFile, conversationID: item.conversationID ?? conversation.id,
                                    reply: reply, model: model)
        let task = Task {
            await run(stream, reply: reply, userMessageID: userID, token: token, onAccepted: onAccepted)
        }
        self.task = task
        let outcome = await task.value
        onIdle?()

        switch outcome {
        case .completed, .cancelled(accepted: true):
            return .delivered
        case .cancelled(accepted: false):
            conversation.remove(userID)
            return .retryLater
        case .failed(.offline?), .failed(.rateLimited?):
            conversation.remove(userID)
            if token == turnToken { status = .queuedOffline }
            return .retryLater
        case .failed:
            return .drop
        }
    }

    /// Stop button: cancel the stream and cut the audio. The text so far stays.
    func stop() {
        task?.cancel()
        task = nil
        turnToken = UUID()
        player.stop()
        streamingMessageID = nil
        if isBusy { status = .done }
        conversation.save()
    }

    // MARK: Live transcripts join the same thread

    func adopt(conversationID: String) {
        conversation.id = conversationID
        conversation.save()
    }

    func appendLive(role: ChatMessage.Role, text: String) {
        guard !text.isEmpty else { return }
        conversation.append(role, text: text, source: .live)
        conversation.save()
        if role == .assistant { SharedStore.saveLastAnswer(text, at: .now) }
    }

    // MARK: - Private

    private func beginTurn() -> UUID {
        task?.cancel()
        player.reset()
        turnToken = UUID()
        streamingMessageID = nil
        status = .sending
        return turnToken
    }

    private func run(_ stream: AsyncThrowingStream<TurnEvent, Error>, reply: ReplyMode,
                     userMessageID: UUID, token: UUID, onAccepted: (() -> Void)? = nil) async -> Outcome {
        if reply == .voice {
            do {
                try await AudioSessionController.shared.activate(for: .turns)
            } catch {
                Log.turn.error("Audio session for playback: \(error.localizedDescription)")
            }
        }
        var accepted = false
        do {
            for try await event in stream {
                guard token == turnToken else { return .cancelled(accepted: accepted) }
                if !accepted {
                    accepted = true
                    onAccepted?()
                }
                apply(event, userMessageID: userMessageID)
            }
            // A cancelled consumer sees the stream end rather than throw.
            guard token == turnToken, !Task.isCancelled else { return .cancelled(accepted: accepted) }
            if isBusy { status = .done }   // stream closed without turn.completed
            streamingMessageID = nil
            conversation.save()
            return .completed
        } catch {
            guard token == turnToken, !(error is CancellationError) else { return .cancelled(accepted: accepted) }
            let apiError = error as? APIError
            streamingMessageID = nil
            status = .failed(apiError?.userMessage ?? "Something went wrong.")
            if !accepted, conversation.message(userMessageID)?.text.isEmpty == true {
                conversation.remove(userMessageID)   // an audio turn that never got a transcript
            }
            if case .quotaExceeded(let resetsAt)? = apiError { onPaywall?(resetsAt) }
            if apiError != .offline { Haptics.failure() }
            Log.turn.error("Turn failed: \(String(describing: error))")
            return .failed(apiError)
        }
    }

    private func apply(_ event: TurnEvent, userMessageID: UUID) {
        switch event {
        case .started(_, let conversationID):
            conversation.id = conversationID
            status = .thinking

        case .transcript(let text):
            // A3: show that we heard them before the model answers.
            conversation.setText(text, for: userMessageID)

        case .textDelta(let delta):
            let id = streamingMessageID ?? conversation.append(.assistant, text: "")
            streamingMessageID = id
            conversation.appendText(delta, to: id)
            status = .streaming

        case .audioSegment(let segment):
            player.enqueue(segment)

        case .audioError(let seq, _):
            player.skip(seq: seq)

        case .completed(_, let text):
            if let id = streamingMessageID {
                if !text.isEmpty { conversation.setText(text, for: id) }   // the server's full text wins
            } else if !text.isEmpty {
                conversation.append(.assistant, text: text)
            }
            streamingMessageID = nil
            status = .done
            conversation.save()
            if let answer = lastAnswer { SharedStore.saveLastAnswer(answer.text, at: answer.at) }

        case .error(let error):
            streamingMessageID = nil
            let noSpeech = error.code == "no_speech"
            if noSpeech, conversation.message(userMessageID)?.text.isEmpty ?? true {
                conversation.remove(userMessageID)
            }
            status = .failed(noSpeech ? "Didn't catch that." : (error.message ?? "Something went wrong."))
            Haptics.failure()

        case .unknown:
            break
        }
    }
}
