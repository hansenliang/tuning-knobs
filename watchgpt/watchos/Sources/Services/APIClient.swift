import Foundation

enum APIError: Error, Equatable, Sendable {
    case unauthorized
    case quotaExceeded(resetsAt: Date?)
    case audioTooLarge
    case unsupportedMediaType
    case rateLimited(retryAfter: TimeInterval?)
    /// No route to the gateway. Audio turns go to the OfflineQueue.
    case offline
    case server(status: Int, code: String?, message: String?)
    case invalidResponse

    var userMessage: String {
        switch self {
        case .unauthorized: "Couldn't sign in to the server."
        case .quotaExceeded: "You're out of free asks for today."
        case .audioTooLarge: "That was too long. Keep it under a minute."
        case .unsupportedMediaType: "That audio format isn't supported."
        case .rateLimited(let after):
            after.map { "Busy. Try again in \(Int($0.rounded(.up))) s." } ?? "Busy. Try again shortly."
        case .offline: "No connection."
        case .server(_, _, let message): message ?? "The server had a problem."
        case .invalidResponse: "Unexpected server response."
        }
    }
}

/// HTTPS client for the gateway (docs/API.md §1–2). The live WebSocket lives in LiveSocket.
///
/// Turns use plain URLSession HTTPS. That's the one transport watchOS allows for every
/// app, on every radio, with no audio-session precondition (TN3135).
actor APIClient {
    private static let tokenAccount = "device-token"

    let baseURL: URL
    private let session: URLSession
    private var pendingRegistration: Task<String, Error>?

    init(baseURL: URL = AppConfig.gatewayURL) {
        self.baseURL = baseURL
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30      // max idle gap between bytes
        config.timeoutIntervalForResource = 120
        config.waitsForConnectivity = false        // fail fast; the OfflineQueue owns retries
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    // MARK: - Device auth

    func token() async throws -> String {
        if let saved = Keychain.string(for: Self.tokenAccount) { return saved }
        return try await register()
    }

    /// `POST /v1/devices`. Concurrent callers share one in-flight registration.
    @discardableResult
    func register() async throws -> String {
        if let pendingRegistration { return try await pendingRegistration.value }
        let task = Task { try await self.performRegistration() }
        pendingRegistration = task
        defer { pendingRegistration = nil }
        return try await task.value
    }

    func invalidateToken() {
        Keychain.delete(Self.tokenAccount)
    }

    private func performRegistration() async throws -> String {
        var request = URLRequest(url: baseURL.appending(path: "v1/devices"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(DeviceRegistrationRequest.current)
        let (data, http) = try await load(request)
        guard (200..<300).contains(http.statusCode) else { throw Self.error(for: http, body: data) }
        let registration = try JSONDecoder().decode(DeviceRegistration.self, from: data)
        Keychain.set(registration.token, for: Self.tokenAccount)
        Log.api.info("Registered device \(registration.deviceID, privacy: .public)")
        return registration.token
    }

    // MARK: - JSON endpoints

    func me() async throws -> Me {
        try await json(Me.self) { token in
            self.makeRequest("v1/me", token: token)
        }
    }

    /// `POST /v1/entitlements/apple` with the StoreKit 2 JWS. The server verifies it; we don't.
    func submitAppleTransaction(jws: String) async throws -> EntitlementResponse {
        let body = try JSONEncoder().encode(["signed_transaction": jws])
        return try await json(EntitlementResponse.self) { token in
            var request = self.makeRequest("v1/entitlements/apple", method: "POST", token: token)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
            return request
        }
    }

    /// `wss://…/v1/live?token=…` (query-param auth per docs/API.md §3).
    func liveURL() async throws -> URL {
        let token = try await token()
        guard var components = URLComponents(url: baseURL.appending(path: "v1/live"),
                                             resolvingAgainstBaseURL: false) else { throw APIError.invalidResponse }
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        guard let url = components.url else { throw APIError.invalidResponse }
        return url
    }

    private func json<T: Decodable>(_ type: T.Type, _ make: (String) throws -> URLRequest) async throws -> T {
        var token = try await token()
        for attempt in 0..<2 {
            let (data, http) = try await load(try make(token))
            if http.statusCode == 401, attempt == 0 {
                invalidateToken()
                token = try await register()
                continue
            }
            guard (200..<300).contains(http.statusCode) else { throw Self.error(for: http, body: data) }
            return try JSONDecoder().decode(T.self, from: data)
        }
        throw APIError.unauthorized
    }

    private func load(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            return (data, http)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: - Turns (NDJSON streaming)

    nonisolated func streamTurn(text: String, conversationID: String?,
                                reply: ReplyMode = .voice, model: ModelChoice = .fast) -> AsyncThrowingStream<TurnEvent, Error> {
        let body = TextTurnRequest(conversationID: conversationID, text: text, reply: reply, model: model)
        return turnStream { token in
            var request = self.makeRequest("v1/turns", method: "POST", token: token)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
            return request
        }
    }

    nonisolated func streamTurn(audioFile: URL, conversationID: String?,
                                reply: ReplyMode = .voice, model: ModelChoice = .fast) -> AsyncThrowingStream<TurnEvent, Error> {
        turnStream { token in
            var query = [URLQueryItem(name: "reply", value: reply.rawValue),
                         URLQueryItem(name: "model", value: model.rawValue)]
            if let conversationID { query.append(URLQueryItem(name: "conversation_id", value: conversationID)) }
            var request = self.makeRequest("v1/turns", method: "POST", query: query, token: token)
            request.setValue("audio/mp4", forHTTPHeaderField: "Content-Type")
            // 60 s of 16 kHz mono AAC is a few hundred KB, well under the 2 MB limit.
            // Loading it whole is simpler than an upload stream.
            request.httpBody = try Data(contentsOf: audioFile)
            return request
        }
    }

    /// Opens the POST, then yields one TurnEvent per NDJSON line. Cancelling the consumer cancels the request.
    private nonisolated func turnStream(
        _ make: @escaping @Sendable (String) throws -> URLRequest
    ) -> AsyncThrowingStream<TurnEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let bytes = try await self.openTurn(make)
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines where !line.isEmpty {
                        do {
                            continuation.yield(try decoder.decode(TurnEvent.self, from: Data(line.utf8)))
                        } catch {
                            Log.api.error("Skipping undecodable NDJSON line: \(error.localizedDescription)")
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Everything before the first byte of the 200 body: auth, status mapping, one 401 re-register.
    private nonisolated func openTurn(_ make: @Sendable (String) throws -> URLRequest) async throws -> URLSession.AsyncBytes {
        var token = try await self.token()
        for attempt in 0..<2 {
            let (bytes, response) = try await session.bytes(for: try make(token))
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if http.statusCode == 200 { return bytes }
            let body = try await Self.collect(bytes, limit: 16_384)
            if http.statusCode == 401, attempt == 0 {
                await invalidateToken()
                token = try await register()
                continue
            }
            throw Self.error(for: http, body: body)
        }
        throw APIError.unauthorized
    }

    // MARK: - Helpers

    private nonisolated func makeRequest(_ path: String, method: String = "GET",
                                         query: [URLQueryItem] = [], token: String) -> URLRequest {
        var url = baseURL.appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func collect(_ bytes: URLSession.AsyncBytes, limit: Int) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= limit { break }
        }
        return data
    }

    static func error(for response: HTTPURLResponse, body: Data) -> APIError {
        let payload = try? JSONDecoder().decode(APIErrorBody.self, from: body)
        switch response.statusCode {
        case 401: return .unauthorized
        case 402: return .quotaExceeded(resetsAt: payload?.resetsAt.flatMap(parseISODate))
        case 413: return .audioTooLarge
        case 415: return .unsupportedMediaType
        case 429:
            let header = response.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            return .rateLimited(retryAfter: payload?.retryAfter ?? header)
        default:
            return .server(status: response.statusCode, code: payload?.code, message: payload?.message)
        }
    }

    static func map(_ error: Error) -> Error {
        if error is APIError || error is CancellationError { return error }
        if let urlError = error as? URLError {
            if urlError.code == .cancelled { return CancellationError() }
            if offlineCodes.contains(urlError.code) { return APIError.offline }
        }
        return error
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed, .timedOut, .internationalRoamingOff, .dataNotAllowed, .callIsActive,
    ]

    /// The server sends `Date.toISOString()`, which includes milliseconds.
    private static func parseISODate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}
