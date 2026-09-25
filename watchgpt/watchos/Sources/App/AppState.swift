import Foundation
import Observation

/// App-wide state and navigation. Owns the services and routes between screens.
@MainActor @Observable
final class AppState {
    enum Screen: Hashable {
        case listening, answer, live, type, offline
    }

    var path: [Screen] = []
    var showPaywall = false
    var notice: String?
    private(set) var paywallResetsAt: Date?
    private(set) var hasConsented: Bool
    private(set) var plan = "trial"
    /// From `GET /v1/me`: the monthly Live allowance minus what's been used this month.
    private(set) var liveSecondsLeftThisMonth: Int?

    let api: APIClient
    let recorder: Recorder
    let player: SegmentPlayer
    let offline: OfflineQueue
    let turns: TurnController
    let live: LiveSession
    let store: Store

    private static let consentKey = "consent.v1.acceptedAt"
    @ObservationIgnored private var didBootstrap = false

    init(api: APIClient = APIClient()) {
        let player = SegmentPlayer()
        let offline = OfflineQueue()
        self.api = api
        self.recorder = Recorder()
        self.player = player
        self.offline = offline
        self.turns = TurnController(api: api, player: player, offline: offline)
        self.live = LiveSession(api: api)
        self.store = Store(api: api)
        self.hasConsented = UserDefaults.standard.object(forKey: Self.consentKey) != nil
        wireServices()
    }

    // MARK: - Lifecycle

    /// Network work starts only after consent. Even the anonymous device registration waits.
    func bootstrap() async {
        guard hasConsented, !didBootstrap else { return }
        didBootstrap = true
        store.start()
        consumePendingLaunch()
        await refreshAccount()
        await offline.retryAll()
    }

    func appBecameActive() {
        consumePendingLaunch()
        guard hasConsented else { return }
        Task { await offline.retryAll() }
    }

    func agreeToConsent() {
        UserDefaults.standard.set(Date(), forKey: Self.consentKey)
        hasConsented = true
        Task { await bootstrap() }
    }

    func refreshAccount() async {
        do {
            let me = try await api.me()
            plan = me.plan
            liveSecondsLeftThisMonth = max(0, me.limits.liveSecondsPerMonth - me.usage.liveSecondsThisMonth)
        } catch {
            Log.api.info("Account refresh skipped: \(String(describing: error))")
        }
    }

    // MARK: - Entry points (URL, complication, Control, Siri)

    func handle(url: URL) {
        guard let action = LaunchAction(url: url) else { return }
        LaunchRouter.shared.request(action)
        consumePendingLaunch()
    }

    /// Consent (C1) comes before the mic, so a launch request waits until the user agrees.
    func consumePendingLaunch() {
        guard hasConsented, let action = LaunchRouter.shared.take() else { return }
        switch action {
        case .listen: startListening()
        case .live: startLive()
        }
    }

    // MARK: - Ask (A1–A4)

    func startListening() {
        guard hasConsented else { return }
        if live.isActive {
            path = [.live]
            return
        }
        guard !recorder.isBusy else { return }
        turns.stop()
        path = [.listening]
        Task {
            do {
                try await recorder.start()
                Haptics.listenStart()
            } catch RecorderError.microphoneDenied {
                notice = "Microphone access is off. Turn it on in Settings › Privacy › Microphone."
                path = []
            } catch {
                Log.audio.error("Recorder start failed: \(error.localizedDescription)")
                notice = "Couldn't start recording."
                path = []
            }
        }
    }

    func sendRecording() {
        guard let url = recorder.stop() else {
            path = []
            releaseAudioIfIdle()
            return
        }
        send(recording: url)
    }

    func cancelRecording() {
        recorder.cancel()
        Haptics.stop()
        path = []
        releaseAudioIfIdle()
    }

    func ask(text: String, reply: ReplyMode) {
        path = [.answer]
        turns.ask(text: text, reply: reply)
    }

    func stopAnswer() {
        turns.stop()
        releaseAudioIfIdle()
    }

    func showThread() { path = [.answer] }
    func showTyping() { path = [.type] }

    private func send(recording url: URL) {
        Haptics.send()
        path = [.answer]
        turns.ask(audioFile: url)
    }

    // MARK: - Live (B1–B4)

    func startLive() {
        guard hasConsented else { return }
        if recorder.isRecording { recorder.cancel() }
        turns.stop()
        live.reset()
        path = [.live]
        Task { await live.start(conversationID: turns.conversation.id) }
    }

    func endLive() {
        live.end()
        Task { await refreshAccount() }
    }

    func finishLive() {
        live.reset()
        path = []
    }

    // MARK: - Paywall / offline

    func presentPaywall(resetsAt: Date?) {
        paywallResetsAt = resetsAt
        showPaywall = true
    }

    func retryOfflineNow() async {
        await offline.retryAll()
    }

    func offlineQueueDrained() {
        if path.last == .offline { path = [.answer] }
    }

    // MARK: - Private

    private func wireServices() {
        recorder.onAutoStop = { [weak self] url in self?.send(recording: url) }   // 60 s cap: send what we have
        player.onDrained = { [weak self] in self?.releaseAudioIfIdle() }
        turns.onIdle = { [weak self] in self?.releaseAudioIfIdle() }
        turns.onPaywall = { [weak self] resetsAt in self?.presentPaywall(resetsAt: resetsAt) }
        turns.onQueuedOffline = { [weak self] in self?.path = [.offline] }
        offline.deliver = { [weak self] item, file in
            guard let self else { return .retryLater }
            return await self.turns.deliver(queued: item, audioFile: file) { [weak self] in
                guard let self else { return }
                if self.path.isEmpty || self.path.last == .offline { self.path = [.answer] }
            }
        }
        live.onConversationID = { [weak self] id in self?.turns.adopt(conversationID: id) }
        live.onUserTranscript = { [weak self] text in self?.turns.appendLive(role: .user, text: text) }
        live.onAssistantReply = { [weak self] text in self?.turns.appendLive(role: .assistant, text: text) }
        store.onEntitlement = { [weak self] response in
            self?.plan = response.plan
            if response.plan == "pro" { self?.showPaywall = false }
        }
    }

    /// Give up the audio session when nothing is using it (battery, and the background-audio glyph).
    private func releaseAudioIfIdle() {
        guard !recorder.isBusy, !live.isActive, !turns.isBusy, !player.isPlaying else { return }
        AudioSessionController.shared.deactivate()
    }
}
