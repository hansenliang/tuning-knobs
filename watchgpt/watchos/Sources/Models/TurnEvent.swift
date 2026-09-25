import Foundation

/// One NDJSON line from `POST /v1/turns` (docs/API.md §2), decoded by its `"type"`.
enum TurnEvent: Sendable, Equatable {
    case started(turnID: String, conversationID: String)
    /// Audio input only: what the server heard. Arrives before any model output.
    case transcript(String)
    case textDelta(String)
    /// A complete, standalone MP3/AAC/WAV file for one sentence. Play in `seq` order.
    case audioSegment(AudioSegment)
    /// TTS failed for one sentence (the server sends this, but docs/API.md doesn't list it yet). Skip that seq.
    case audioError(seq: Int, message: String?)
    case completed(turnID: String, text: String)
    /// Mid-stream failure. The server closes the stream after this.
    case error(TurnStreamError)
    /// A type this client doesn't know. Ignored, so the server can add events safely.
    case unknown(type: String)
}

struct AudioSegment: Sendable, Equatable {
    let seq: Int
    let format: String     // "mp3" | "aac" | "wav"
    let text: String?
    let data: Data
}

struct TurnStreamError: Error, Sendable, Equatable {
    let code: String
    let message: String?
    let retryable: Bool
}

extension TurnEvent: Decodable {
    private enum CodingKeys: String, CodingKey {
        case type
        case turnID = "turn_id"
        case conversationID = "conversation_id"
        case text, seq, format, data, code, message, retryable
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "turn.started":
            self = .started(turnID: try c.decode(String.self, forKey: .turnID),
                            conversationID: try c.decode(String.self, forKey: .conversationID))
        case "transcript":
            self = .transcript(try c.decode(String.self, forKey: .text))
        case "text.delta":
            self = .textDelta(try c.decode(String.self, forKey: .text))
        case "audio.segment":
            // JSONDecoder's default dataDecodingStrategy is base64, which matches `data`.
            self = .audioSegment(AudioSegment(
                seq: try c.decode(Int.self, forKey: .seq),
                format: try c.decodeIfPresent(String.self, forKey: .format) ?? "mp3",
                text: try c.decodeIfPresent(String.self, forKey: .text),
                data: try c.decode(Data.self, forKey: .data)))
        case "audio.error":
            self = .audioError(seq: try c.decode(Int.self, forKey: .seq),
                               message: try c.decodeIfPresent(String.self, forKey: .message))
        case "turn.completed":
            self = .completed(turnID: try c.decodeIfPresent(String.self, forKey: .turnID) ?? "",
                              text: try c.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "error":
            self = .error(TurnStreamError(
                code: try c.decodeIfPresent(String.self, forKey: .code) ?? "unknown",
                message: try c.decodeIfPresent(String.self, forKey: .message),
                retryable: try c.decodeIfPresent(Bool.self, forKey: .retryable) ?? false))
        default:
            self = .unknown(type: type)
        }
    }
}
