import Foundation

/// Build-time configuration. `GATEWAY_URL` comes from project.yml → Info.plist.
enum AppConfig {
    static let gatewayURL: URL = {
        if let raw = Bundle.main.object(forInfoDictionaryKey: "GATEWAY_URL") as? String,
           let url = URL(string: raw), url.scheme != nil, url.host() != nil {
            return url
        }
        return URL(string: "http://localhost:8787")!
    }()

    static let appVersion: String =
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"

    // Placeholders. App Review (3.1.2) needs working links on the subscription screen.
    static let termsURL = URL(string: "https://watchgpt.example/terms")!
    static let privacyURL = URL(string: "https://watchgpt.example/privacy")!
}
