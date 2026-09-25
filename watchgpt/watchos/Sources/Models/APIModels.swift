import Foundation

// Request/response bodies for docs/API.md §1–2. Explicit CodingKeys throughout.
// A key strategy would turn `device_id` into `deviceId`, not `deviceID`.

enum ReplyMode: String, Codable, Sendable {
    case voice   // text + audio.segment events
    case text    // no TTS (silent input, C4)
}

enum ModelChoice: String, Codable, Sendable {
    case fast, smart
}

struct Limits: Codable, Sendable, Equatable {
    let turnsPerDay: Int
    let liveSecondsPerMonth: Int

    enum CodingKeys: String, CodingKey {
        case turnsPerDay = "turns_per_day"
        case liveSecondsPerMonth = "live_seconds_per_month"
    }
}

struct DeviceRegistrationRequest: Encodable, Sendable {
    let platform: String
    let appVersion: String
    let locale: String

    enum CodingKeys: String, CodingKey {
        case platform, locale
        case appVersion = "app_version"
    }

    static var current: DeviceRegistrationRequest {
        .init(platform: "watchOS", appVersion: AppConfig.appVersion, locale: Locale.current.identifier(.bcp47))
    }
}

struct DeviceRegistration: Decodable, Sendable {
    let deviceID: String
    let token: String
    let plan: String
    let limits: Limits?

    enum CodingKeys: String, CodingKey {
        case token, plan, limits
        case deviceID = "device_id"
    }
}

struct Me: Decodable, Sendable {
    struct Usage: Decodable, Sendable {
        let turnsToday: Int
        let liveSecondsThisMonth: Int

        enum CodingKeys: String, CodingKey {
            case turnsToday = "turns_today"
            case liveSecondsThisMonth = "live_seconds_this_month"
        }
    }

    let deviceID: String
    let plan: String
    let limits: Limits
    let usage: Usage

    enum CodingKeys: String, CodingKey {
        case plan, limits, usage
        case deviceID = "device_id"
    }
}

struct EntitlementResponse: Decodable, Sendable {
    let plan: String
    let limits: Limits?
}

struct TextTurnRequest: Encodable, Sendable {
    let conversationID: String?
    let text: String
    let reply: ReplyMode
    let model: ModelChoice

    enum CodingKeys: String, CodingKey {
        case text, reply, model
        case conversationID = "conversation_id"
    }
}

/// Error body for non-2xx responses: `{ "code", "message", "resets_at"?, "retry_after"? }`.
struct APIErrorBody: Decodable, Sendable {
    let code: String?
    let message: String?
    let resetsAt: String?
    let retryAfter: Double?

    enum CodingKeys: String, CodingKey {
        case code, message
        case resetsAt = "resets_at"
        case retryAfter = "retry_after"
    }
}
