import AVFoundation

/// Owns the one AVAudioSession configuration for push-to-talk turns and Live.
@MainActor
final class AudioSessionController {
    static let shared = AudioSessionController()

    enum Mode { case turns, live }

    private var configuredMode: Mode?

    /// Sets the category if needed, then activates the session.
    ///
    /// watchOS: use the async `activate(options:)`. The synchronous `setActive(true)`
    /// returns without error on the watch but doesn't grant low-level networking
    /// (forum 773362, confirmed on watchOS 26.6). Live mode must call this before
    /// opening its NWConnection.
    func activate(for mode: Mode) async throws {
        let session = AVAudioSession.sharedInstance()
        if configuredMode != mode {
            switch mode {
            case .turns:
                try session.setCategory(.playAndRecord, mode: .default, policy: .default,
                                        options: [.allowBluetoothHFP])
            case .live:
                // .voiceChat asks the system for its voice-processing path. LiveAudioIO also
                // enables AVAudioEngine voice processing for echo cancellation.
                try session.setCategory(.playAndRecord, mode: .voiceChat, policy: .default,
                                        options: [.allowBluetoothHFP])
            }
            configuredMode = mode
        }
        try await reactivate()
    }

    /// Re-activates without deactivating first.
    ///
    /// Workaround for FB24377808: watchOS revokes the audio-session networking grant
    /// about 36 s after each activate(). Calling activate() again every ~30 s pushes the
    /// deadline back (forum 841590: a socket held 11.5 min). The behavior is undocumented;
    /// re-test on every watchOS release.
    func reactivate() async throws {
        let activated = try await AVAudioSession.sharedInstance().activate(options: [])
        if !activated { Log.audio.error("activate(options:) returned false") }
    }

    func deactivate() {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            Log.audio.error("Deactivate failed: \(error.localizedDescription)")
        }
    }
}

enum Permissions {
    /// Mic permission. The system prompt appears only here, so ConsentView (C1) must come first.
    static func requestMicrophone() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default: break
        }
        return await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
