import AVFoundation
import Foundation
import Observation
import os
import WatchKit

/// Hands-free, full-duplex Live mode (B1–B4) over `WSS /v1/live` (docs/API.md §3).
///
/// Order of operations (the watchOS rules make this order mandatory):
///  1. `.playAndRecord` category, then `await activate()`. Only after that may we open an
///     NWConnection (TN3135).
///  2. Start the engine. Mic frames collect in `FrameSink` until `session.ready`.
///  3. Connect, send `session.start` as the first frame, wait for `session.ready`, then stream PCM16.
///  4. Every 30 s, re-activate the audio session (FB24377808 workaround for the ~36 s revocation).
///  5. On an unexpected drop: re-activate, reconnect with backoff (0, 250 ms, 500 ms, 1 s, then
///     1 s until the resume window closes), and send `session.start` with `resume_session_id`.
@MainActor @Observable
final class LiveSession {
    enum Phase: Equatable {
        case idle, connecting, listening, speaking, reconnecting, interrupted, ended
    }

    enum EndReason: Equatable {
        case user, mutedTooLong, quotaExceeded, maxSessionLength, unauthorized, upstreamFailure, connectionLost
        case failed(String)

        var message: String? {
            switch self {
            case .user: nil
            case .mutedTooLong: "Ended after a minute on mute."
            case .quotaExceeded: "You're out of Live minutes."
            case .maxSessionLength: "That's the longest a Live session can run."
            case .unauthorized: "Couldn't sign in to Live."
            case .upstreamFailure: "Live is unavailable right now."
            case .connectionLost: "Connection lost."
            case .failed(let text): text
            }
        }
    }

    // MARK: UI state

    private(set) var phase: Phase = .idle
    private(set) var isMuted = false
    private(set) var userCaption = ""
    private(set) var assistantCaption = ""
    private(set) var micLevel: Float = 0
    private(set) var outputLevel: Float = 0
    /// Talked this session, across server sessions that couldn't be resumed.
    private(set) var secondsUsed = 0
    /// Allowance left for this session (`max_seconds` minus `usage.live_seconds`).
    private(set) var secondsLeft: Int?
    private(set) var endReason: EndReason?

    var isActive: Bool { phase != .idle && phase != .ended }

    // MARK: Hooks (AppState merges Live into the shared thread)

    @ObservationIgnored var onConversationID: ((String) -> Void)?
    @ObservationIgnored var onUserTranscript: ((String) -> Void)?
    @ObservationIgnored var onAssistantReply: ((String) -> Void)?

    // MARK: Tuning

    private static let reconnectBackoff: [Duration] = [.zero, .milliseconds(250), .milliseconds(500), .seconds(1)]
    private static let keepAliveInterval: Duration = .seconds(30)
    private static let mutedIdleLimit: Duration = .seconds(60)
    private static let defaultResumeWindow: TimeInterval = 15

    // MARK: Internals

    private let api: APIClient
    private let audio = LiveAudioIO()
    private let sink = FrameSink()
    @ObservationIgnored private var socket: LiveSocket?
    @ObservationIgnored private var socketTask: Task<Void, Never>?
    @ObservationIgnored private var keepAliveTask: Task<Void, Never>?
    @ObservationIgnored private var reconnectTask: Task<Void, Never>?
    @ObservationIgnored private var mutedIdleTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    @ObservationIgnored private var conversationID: String?
    @ObservationIgnored private var sessionID: String?
    @ObservationIgnored private var resumeWindow: TimeInterval = 15
    @ObservationIgnored private var maxSeconds: Int?
    @ObservationIgnored private var serverSeconds = 0     // latest usage.live_seconds (current server session)
    @ObservationIgnored private var carriedSeconds = 0    // from earlier server sessions we couldn't resume
    @ObservationIgnored private var reconnectAttempt = 0
    @ObservationIgnored private var droppedAt: Date?
    @ObservationIgnored private var didReauthorize = false
    @ObservationIgnored private var pendingEndReason: EndReason?

    init(api: APIClient) {
        self.api = api
    }

    // MARK: - Public controls

    func start(conversationID: String?) async {
        guard !isActive else { return }
        reset()
        self.conversationID = conversationID
        phase = .connecting

        guard await Permissions.requestMicrophone() else {
            return finish(.failed("Microphone access is off. Turn it on in Settings."))
        }
        guard phase == .connecting else { return }   // ended while the prompt was up

        do {
            try await AudioSessionController.shared.activate(for: .live)
            guard phase == .connecting else { return }
            wireAudioCallbacks()
            try audio.start()
        } catch {
            Log.live.error("Audio start failed: \(error.localizedDescription)")
            return finish(.failed("Couldn't start the microphone."))
        }
        observeAudioSession()
        startKeepAlive()
        await openSocket()
    }

    /// B3: mute stops sending mic audio but keeps the session. After 60 s muted it ends itself.
    func toggleMute() {
        guard isActive else { return }
        isMuted.toggle()
        sink.setMuted(isMuted)
        mutedIdleTask?.cancel()
        mutedIdleTask = nil
        if isMuted {
            mutedIdleTask = Task { [weak self] in
                try? await Task.sleep(for: Self.mutedIdleLimit)
                guard !Task.isCancelled else { return }
                self?.end(reason: .mutedTooLong)
            }
        }
        Haptics.toggle()
    }

    /// Barge-in by tap: silence the reply now and tell the server to stop generating.
    func interruptReply() {
        guard phase == .speaking else { return }
        audio.flushPlayback()
        socket?.send(.responseCancel)
        assistantCaption = ""
        phase = .listening
    }

    /// Manual-VAD "I'm done talking". Unused with `vad: "server"`, kept for a tap-to-send variant.
    func commitInput() {
        socket?.send(.inputCommit)
    }

    func end(reason: EndReason = .user) {
        guard isActive else { return }
        if let socket {
            self.socket = nil
            socket.send(.sessionEnd)   // graceful: server flushes usage and bills now, not after the resume window
            socket.close()
        }
        finish(reason)
    }

    /// Back to idle after the summary (B4) is dismissed.
    func reset() {
        guard !isActive else { return }
        phase = .idle
        isMuted = false
        userCaption = ""
        assistantCaption = ""
        micLevel = 0
        outputLevel = 0
        secondsUsed = 0
        secondsLeft = nil
        endReason = nil
        sessionID = nil
        resumeWindow = Self.defaultResumeWindow
        maxSeconds = nil
        serverSeconds = 0
        carriedSeconds = 0
        reconnectAttempt = 0
        droppedAt = nil
        didReauthorize = false
        pendingEndReason = nil
        sink.reset()
    }

    /// After a call or Siri. watchOS can't restart capture from the background, so this
    /// runs automatically only while frontmost; otherwise the UI offers "Tap to resume".
    func resumeAfterInterruption() async {
        guard phase == .interrupted else { return }
        do {
            try await AudioSessionController.shared.reactivate()
            try audio.restart()
        } catch {
            Log.live.error("Resume after interruption failed: \(error.localizedDescription)")
            return
        }
        if socket == nil {
            phase = .reconnecting
            scheduleReconnect()
        } else {
            phase = .listening
        }
    }

    // MARK: - Socket

    private func openSocket() async {
        let url: URL
        do {
            url = try await api.liveURL()
        } catch {
            Log.live.error("No live URL: \(String(describing: error))")
            return scheduleReconnect()
        }
        guard isActive else { return }

        let socket = LiveSocket(url: url)
        self.socket?.cancel()
        self.socket = socket
        socketTask?.cancel()
        // All socket events (text *and* binary) go through one ordered stream on the main
        // actor. That way a `speech.started` flush can never overtake audio that arrived before it.
        socketTask = Task { [weak self] in
            for await event in socket.events {
                guard let self else { return }
                self.handleSocket(event, from: socket)
            }
        }
        socket.start()
    }

    private func handleSocket(_ event: LiveSocket.Event, from source: LiveSocket) {
        guard source === socket, isActive else { return }   // ignore a replaced socket
        switch event {
        case .connected:
            // `session.start` must be the first frame. Mic audio stays in the sink until `session.ready`.
            source.send(.start(conversationID: conversationID, vad: .server, resumeSessionID: sessionID))
        case .text(let text):
            if let event = LiveServerEvent.decode(text) { handleServer(event) }
        case .binary(let pcm):
            guard phase != .interrupted else { return }
            outputLevel = min(1, audio.enqueuePlayback(pcm) * 4)
            if phase == .listening { phase = .speaking }
        case .closed(let close):
            socketClosed(close)
        }
    }

    private func handleServer(_ event: LiveServerEvent) {
        switch event {
        case .ready(let info):
            if sessionID != nil, !info.resumed {
                // The server couldn't resume, so this is a fresh session. Its usage counter restarts at 0.
                carriedSeconds += serverSeconds
                serverSeconds = 0
                assistantCaption = ""
                audio.flushPlayback()
            }
            let isFirstReady = sessionID == nil
            sessionID = info.sessionID
            resumeWindow = info.resumeWindowSeconds ?? Self.defaultResumeWindow
            maxSeconds = info.maxSeconds
            if !info.conversationID.isEmpty {
                conversationID = info.conversationID
                onConversationID?(info.conversationID)
            }
            reconnectAttempt = 0
            droppedAt = nil
            if let socket { sink.open(socket) }   // flushes up to 1.5 s of audio captured meanwhile
            if phase != .interrupted { phase = .listening }
            updateMeter()
            if isFirstReady { Haptics.liveReady() }

        case .speechStarted:
            // Barge-in: the user is talking over the reply. Drop queued audio within one frame.
            audio.flushPlayback()
            userCaption = ""
            assistantCaption = ""
            if phase == .speaking { phase = .listening }

        case .speechStopped:
            break

        case .userTranscript(let text):
            userCaption = text
            onUserTranscript?(text)

        case .assistantDelta(let text):
            assistantCaption += text

        case .responseDone(let text):
            onAssistantReply?(text)

        case .usage(let seconds):
            serverSeconds = Int(seconds.rounded())
            updateMeter()

        case .error(let code, let message):
            Log.live.error("Server error \(code, privacy: .public): \(message, privacy: .public)")
            // A close frame usually follows. Remember why, for the summary screen.
            switch code {
            case "quota_exceeded": pendingEndReason = .quotaExceeded
            case "max_session_length": pendingEndReason = .maxSessionLength
            default: pendingEndReason = .failed(message.isEmpty ? "Live had a problem." : message)
            }

        case .unknown:
            break
        }
    }

    private func socketClosed(_ close: LiveSocket.Close) {
        Log.live.info("Socket closed code=\(close.code ?? -1) error=\(close.error ?? "-", privacy: .public)")
        socket = nil
        sink.detach()

        switch close.code.flatMap(LiveCloseCode.init(rawValue:)) {
        case .unauthorized?:
            guard !didReauthorize else { return finish(.unauthorized) }
            // Token rejected: re-register once and start a fresh session. A new device
            // can't resume the old one, so clear sessionID.
            didReauthorize = true
            sessionID = nil
            phase = .reconnecting
            reconnectTask = Task { [weak self] in
                guard let self else { return }
                await self.api.invalidateToken()
                _ = try? await self.api.register()
                self.reconnectTask = nil
                await self.openSocket()
            }
        case .quotaExceeded?:
            finish(.quotaExceeded)
        case .maxSessionLength?:
            finish(.maxSessionLength)
        case .upstreamFailure?:
            finish(.upstreamFailure)
        case .normal?:
            finish(pendingEndReason ?? .connectionLost)
        case nil:
            // Grant revoked, radio handoff, server restart: resumable.
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        guard isActive, reconnectTask == nil else { return }
        let now = Date()
        let droppedAt = self.droppedAt ?? now
        self.droppedAt = droppedAt

        // Before the first `session.ready` there's nothing to resume, so give up after
        // the backoff list. After that, keep trying (1 s apart) until the resume window closes.
        let exhausted = sessionID == nil
            ? reconnectAttempt >= Self.reconnectBackoff.count
            : now.timeIntervalSince(droppedAt) > resumeWindow
        if exhausted { return finish(pendingEndReason ?? .connectionLost) }

        let delay = Self.reconnectBackoff[min(reconnectAttempt, Self.reconnectBackoff.count - 1)]
        reconnectAttempt += 1
        if phase != .interrupted { phase = .reconnecting }

        reconnectTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled, self.isActive else { return }
            // The drop is often the grant revocation itself. Re-activate before dialing, or the
            // new NWConnection just sits in .waiting(ENETDOWN).
            do {
                try await AudioSessionController.shared.reactivate()
            } catch {
                Log.live.error("Re-activate before reconnect failed: \(error.localizedDescription)")
            }
            self.reconnectTask = nil
            await self.openSocket()
        }
    }

    // MARK: - Audio

    private func wireAudioCallbacks() {
        let sink = self.sink
        audio.onFrame = { [weak self] frame, level in
            sink.push(frame)
            Task { @MainActor [weak self] in self?.micLevel = min(1, level * 4) }
        }
        audio.onPlaybackDrained = { [weak self] in
            Task { @MainActor [weak self] in self?.playbackDrained() }
        }
        audio.onConfigurationChange = { [weak self] in
            Task { @MainActor [weak self] in self?.restartAudioAfterRouteChange() }
        }
    }

    private func playbackDrained() {
        outputLevel = 0
        if phase == .speaking { phase = .listening }
    }

    private func restartAudioAfterRouteChange() {
        guard isActive, phase != .interrupted else { return }
        do {
            try audio.restart()
        } catch {
            Log.live.error("Engine restart after route change failed: \(error.localizedDescription)")
            phase = .interrupted
        }
    }

    private func startKeepAlive() {
        keepAliveTask?.cancel()
        keepAliveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.keepAliveInterval)
                guard !Task.isCancelled, self != nil else { return }
                // FB24377808: the networking grant is revoked ~36 s after each activate().
                // Re-activating (without deactivating) resets that clock. Undocumented.
                do {
                    try await AudioSessionController.shared.reactivate()
                } catch {
                    Log.live.error("Keep-alive activate failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func observeAudioSession() {
        let token = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let rawOptions = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            MainActor.assumeIsolated { self?.handleInterruption(type, options) }
        }
        observers.append(token)
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType?, _ options: AVAudioSession.InterruptionOptions) {
        guard isActive, let type else { return }
        switch type {
        case .began:
            // The system has stopped our engine. Keep the socket. If it drops meanwhile, the
            // resume logic covers it, and the server keeps the session for `resume_window_s`.
            audio.flushPlayback()
            phase = .interrupted
        case .ended:
            if options.contains(.shouldResume), WKApplication.shared().applicationState == .active {
                Task { await resumeAfterInterruption() }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Teardown

    private func updateMeter() {
        secondsUsed = carriedSeconds + serverSeconds
        secondsLeft = maxSeconds.map { max(0, $0 - serverSeconds) }
    }

    private func finish(_ reason: EndReason) {
        guard isActive else { return }
        socket?.cancel()
        socket = nil
        socketTask?.cancel()
        keepAliveTask?.cancel()
        reconnectTask?.cancel()
        mutedIdleTask?.cancel()
        socketTask = nil
        keepAliveTask = nil
        reconnectTask = nil
        mutedIdleTask = nil
        sink.detach()
        audio.stop()
        for token in observers { NotificationCenter.default.removeObserver(token) }
        observers.removeAll()
        AudioSessionController.shared.deactivate()

        endReason = reason
        micLevel = 0
        outputLevel = 0
        phase = .ended
        if reason == .user { Haptics.stop() } else { Haptics.failure() }
    }
}

/// Hands mic frames from the audio tap thread to whichever socket is current.
/// While no socket is ready (connecting, reconnecting) it keeps the last 1.5 s, so a
/// short blip doesn't swallow the start of what the user said.
final class FrameSink: Sendable {
    private struct State: Sendable {
        var socket: LiveSocket?
        var muted = false
        var backlog: [Data] = []
    }

    private static let maxBacklog = 15   // 15 × 100 ms
    private let state = OSAllocatedUnfairLock(initialState: State())

    func push(_ frame: Data) {
        // Sending under the lock keeps backlog and live frames in order. NWConnection.send only enqueues.
        state.withLock { state in
            guard !state.muted else { return }
            if let socket = state.socket {
                socket.send(binary: frame)
            } else {
                state.backlog.append(frame)
                if state.backlog.count > Self.maxBacklog {
                    state.backlog.removeFirst(state.backlog.count - Self.maxBacklog)
                }
            }
        }
    }

    /// Call on `session.ready`: flushes the backlog, then streams live.
    func open(_ socket: LiveSocket) {
        state.withLock { state in
            for frame in state.backlog { socket.send(binary: frame) }
            state.backlog.removeAll()
            state.socket = socket
        }
    }

    /// The socket dropped. Start buffering again.
    func detach() {
        state.withLock { $0.socket = nil }
    }

    func setMuted(_ muted: Bool) {
        state.withLock { state in
            state.muted = muted
            if muted { state.backlog.removeAll() }
        }
    }

    func reset() {
        state.withLock { $0 = State() }
    }
}
