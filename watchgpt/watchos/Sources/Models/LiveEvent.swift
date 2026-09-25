import Foundation

// Live mode wire types (docs/API.md §3). Audio travels as binary PCM16 frames;
// everything below is a JSON text frame.

/// Server → client JSON frames.
enum LiveServerEvent: Sendable, Equatable {
    case ready(LiveSessionInfo)
    /// The user started talking. The client must flush queued playback (barge-in).
    case speechStarted
    case speechStopped
    case userTranscript(String)
    case assistantDelta(String)
    case responseDone(String)
    /// Seconds billed so far in this server session. Arrives about once a second.
    case usage(liveSeconds: Double)
    case error(code: String, message: String)
    case unknown(type: String)

    static func decode(_ text: String) -> LiveServerEvent? {
        try? JSONDecoder().decode(LiveServerEvent.self, from: Data(text.utf8))
    }
}

struct LiveSessionInfo: Sendable, Equatable {
    let sessionID: String
    let conversationID: String
    let sampleRate: Int
    let maxSeconds: Int?
    /// How long the server keeps a dropped session resumable. The prototype server doesn't send it yet.
    let resumeWindowSeconds: Double?
    let resumed: Bool
}

extension LiveServerEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case sessionID = "session_id"
        case conversationID = "conversation_id"
        case sampleRate = "sample_rate"
        case maxSeconds = "max_seconds"
        case resumeWindow = "resume_window_s"
        case resumed, text, code, message
        case liveSeconds = "live_seconds"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "session.ready":
            self = .ready(LiveSessionInfo(
                sessionID: try c.decode(String.self, forKey: .sessionID),
                conversationID: try c.decodeIfPresent(String.self, forKey: .conversationID) ?? "",
                sampleRate: try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 24_000,
                maxSeconds: try c.decodeIfPresent(Double.self, forKey: .maxSeconds).map { Int($0) },
                resumeWindowSeconds: try c.decodeIfPresent(Double.self, forKey: .resumeWindow),
                resumed: try c.decodeIfPresent(Bool.self, forKey: .resumed) ?? false))
        case "speech.started": self = .speechStarted
        case "speech.stopped": self = .speechStopped
        case "transcript.user": self = .userTranscript(try c.decode(String.self, forKey: .text))
        case "transcript.assistant.delta": self = .assistantDelta(try c.decode(String.self, forKey: .text))
        case "response.done": self = .responseDone(try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "usage": self = .usage(liveSeconds: try c.decode(Double.self, forKey: .liveSeconds))
        case "error":
            self = .error(code: try c.decodeIfPresent(String.self, forKey: .code) ?? "unknown",
                          message: try c.decodeIfPresent(String.self, forKey: .message) ?? "")
        default:
            self = .unknown(type: type)
        }
    }
}

/// Client → server JSON frames.
enum LiveClientMessage: Encodable, Sendable {
    enum VAD: String, Encodable, Sendable { case server, manual }

    /// Must be the first frame on every connection, including a resume.
    case start(conversationID: String?, vad: VAD, resumeSessionID: String?)
    case inputCommit
    case responseCancel
    case sessionEnd

    private enum CodingKeys: String, CodingKey {
        case type, vad
        case conversationID = "conversation_id"
        case resumeSessionID = "resume_session_id"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .start(conversationID, vad, resumeSessionID):
            try c.encode("session.start", forKey: .type)
            try c.encodeIfPresent(conversationID, forKey: .conversationID)
            try c.encode(vad, forKey: .vad)
            try c.encodeIfPresent(resumeSessionID, forKey: .resumeSessionID)
        case .inputCommit: try c.encode("input.commit", forKey: .type)
        case .responseCancel: try c.encode("response.cancel", forKey: .type)
        case .sessionEnd: try c.encode("session.end", forKey: .type)
        }
    }
}

/// WebSocket close codes the gateway uses. Anything else is an unexpected drop, so the client resumes.
enum LiveCloseCode: Int, Sendable {
    case normal = 1000
    case unauthorized = 4001
    case quotaExceeded = 4002
    case maxSessionLength = 4003
    case upstreamFailure = 4500
}
