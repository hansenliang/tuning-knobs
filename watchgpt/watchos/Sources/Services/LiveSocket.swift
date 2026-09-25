import Foundation
import Network

/// A small WebSocket client on Network.framework.
///
/// Why not URLSessionWebSocketTask: on watchOS the low-level networking grant goes to our
/// process while an audio session is active, but URLSession runs out of process. Its
/// WebSocket task is denied in practice (TN3135, forum 773362). NWConnection runs
/// in-process, so it works once `AVAudioSession.activate()` has completed.
///
/// One instance is one connection. Reconnecting means building a new LiveSocket.
/// Thread safety: all mutable state is touched only on `queue`, and NWConnection.send is
/// thread-safe. That's why this is `@unchecked Sendable`.
final class LiveSocket: @unchecked Sendable {
    enum Event: Sendable {
        case connected
        case text(String)
        case binary(Data)
        /// Terminal. `code` is the WebSocket close code, if the peer sent one.
        case closed(Close)
    }

    struct Close: Sendable, Equatable {
        var code: Int?
        var reason: String?
        var error: String?
    }

    let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "app.watchgpt.live.socket", qos: .userInitiated)

    // Only touched on `queue`.
    private var finished = false
    private var isReady = false
    private var watchdog: DispatchWorkItem?

    private static let connectTimeout: TimeInterval = 5
    /// How long to tolerate `.waiting` or a non-viable path before calling it a drop.
    /// Short, because the fix (re-activate the audio session, redial) is cheap.
    private static let stallTimeout: TimeInterval = 2

    init(url: URL) {
        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true   // 100 ms audio frames; don't let Nagle batch them
        let parameters = NWParameters(tls: url.scheme == "wss" ? NWProtocolTLS.Options() : nil, tcp: tcp)

        let websocket = NWProtocolWebSocket.Options()
        websocket.autoReplyPing = true
        websocket.maximumMessageSize = 1 << 20
        parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)

        // A `.url` endpoint gives the WebSocket handshake its Host header and /v1/live?token=… path.
        connection = NWConnection(to: .url(url), using: parameters)

        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        events = stream
        self.continuation = continuation
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in self?.handle(state) }
        connection.viabilityUpdateHandler = { [weak self] viable in self?.viabilityChanged(viable) }
        connection.start(queue: queue)
        queue.async { self.arm(after: Self.connectTimeout, reason: "connect timeout") }
    }

    // MARK: Sending

    func send(_ message: LiveClientMessage) {
        guard let data = try? JSONEncoder().encode(message) else { return }
        send(data, opcode: .text)
    }

    func send(binary: Data) {
        send(binary, opcode: .binary)
    }

    private func send(_ data: Data, opcode: NWProtocolWebSocket.Opcode) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        let context = NWConnection.ContentContext(identifier: "ws", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true,
                        completion: .contentProcessed { error in
            if let error { Log.live.debug("send failed: \(String(describing: error))") }
        })
    }

    // MARK: Closing

    /// Graceful: sends a close frame after anything already queued (e.g. `session.end`),
    /// then tears down. Emits no `.closed` event, because the caller asked for this.
    func close() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            disarm()
            continuation.finish()
            let metadata = NWProtocolWebSocket.Metadata(opcode: .close)
            metadata.closeCode = .protocolCode(.normalClosure)
            let context = NWConnection.ContentContext(identifier: "close", metadata: [metadata])
            let connection = self.connection
            connection.send(content: nil, contentContext: context, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            queue.asyncAfter(deadline: .now() + 1) { connection.cancel() }   // a dead link may never complete the send
        }
    }

    /// Immediate teardown with no event (used when a newer socket replaces this one).
    func cancel() {
        queue.async { [self] in
            guard !finished else { return }
            finished = true
            disarm()
            continuation.finish()
            connection.cancel()
        }
    }

    // MARK: Connection lifecycle (on `queue`)

    private func handle(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isReady = true
            disarm()
            continuation.yield(.connected)
            receive()
        case .waiting(let error):
            // TN3135: without the audio-session grant, a connection sits in .waiting(ENETDOWN)
            // indefinitely. Surface it fast so LiveSession can re-activate and redial.
            arm(after: Self.stallTimeout, reason: "waiting: \(error)")
        case .failed(let error):
            finish(Close(code: nil, reason: nil, error: "\(error)"))
        case .cancelled:
            finish(Close(code: nil, reason: nil, error: "cancelled"))
        default:
            break
        }
    }

    private func viabilityChanged(_ viable: Bool) {
        // The ~36 s grant revocation shows up here first, before the socket errors with POSIX 50/9.
        if viable {
            if isReady { disarm() }
        } else {
            arm(after: Self.stallTimeout, reason: "path not viable")
        }
    }

    private func receive() {
        connection.receiveMessage { [weak self] content, context, _, error in
            guard let self, !self.finished else { return }
            if let error {
                self.finish(Close(code: nil, reason: nil, error: "\(error)"))
                return
            }
            let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition)
                as? NWProtocolWebSocket.Metadata
            switch metadata?.opcode {
            case .text?:
                if let content, let text = String(data: content, encoding: .utf8) {
                    self.continuation.yield(.text(text))
                }
            case .binary?:
                if let content { self.continuation.yield(.binary(content)) }
            case .close?:
                self.finish(Close(code: metadata.map { Self.number(for: $0.closeCode) },
                                  reason: content.flatMap { String(data: $0, encoding: .utf8) },
                                  error: nil))
                return
            case nil where content == nil:
                // No frame and no error: the peer went away without a close frame.
                self.finish(Close(code: nil, reason: nil, error: "eof"))
                return
            default:
                break   // ping/pong: autoReplyPing answers these
            }
            self.receive()
        }
    }

    private func finish(_ close: Close) {
        guard !finished else { return }
        finished = true
        disarm()
        continuation.yield(.closed(close))
        continuation.finish()
        connection.cancel()
    }

    private func arm(after seconds: TimeInterval, reason: String) {
        watchdog?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.finish(Close(code: nil, reason: nil, error: reason))
        }
        watchdog = item
        queue.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    private func disarm() {
        watchdog?.cancel()
        watchdog = nil
    }

    /// The gateway's 4xxx codes fall in the private-use range (RFC 6455 §7.4.2).
    private static func number(for code: NWProtocolWebSocket.CloseCode) -> Int {
        switch code {
        case .protocolCode(let defined): return Int(defined.rawValue)
        case .applicationCode(let value): return Int(value)
        case .privateCode(let value): return Int(value)
        @unknown default: return 0
        }
    }
}
