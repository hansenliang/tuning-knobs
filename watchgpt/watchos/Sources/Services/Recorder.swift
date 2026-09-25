import AVFoundation
import Observation

enum RecorderError: Error {
    case microphoneDenied
    case couldNotStart
}

/// Push-to-talk capture (A2): AAC in .m4a, 16 kHz mono, capped at 60 s, uploaded as `audio/mp4`.
/// Metering drives the waveform bars.
@MainActor @Observable
final class Recorder: NSObject {
    static let maxDuration: TimeInterval = 60
    static let barCount = 8
    private static let minimumDuration: TimeInterval = 0.4   // shorter taps count as a cancel

    private static let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    private(set) var isRecording = false
    /// True from the tap until recording starts or fails, so the audio session isn't released mid-start.
    private(set) var isPreparing = false
    private(set) var elapsed: TimeInterval = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: Recorder.barCount)

    var isBusy: Bool { isRecording || isPreparing }

    /// Called when the 60 s cap stops the recording by itself. The caller should send it.
    @ObservationIgnored var onAutoStop: ((URL) -> Void)?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var meterTask: Task<Void, Never>?

    func start() async throws {
        guard !isBusy else { return }
        isPreparing = true
        defer { isPreparing = false }

        guard await Permissions.requestMicrophone() else { throw RecorderError.microphoneDenied }
        try await AudioSessionController.shared.activate(for: .turns)

        let url = FileManager.default.temporaryDirectory.appending(path: "ask-\(UUID().uuidString).m4a")
        let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        guard recorder.record(forDuration: Self.maxDuration) else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        isRecording = true
        elapsed = 0
        levels = Array(repeating: 0, count: Self.barCount)
        startMetering()
    }

    /// Stops and returns the file, or nil if nothing useful was recorded.
    func stop() -> URL? {
        guard let recorder, isRecording else { return nil }
        let duration = recorder.currentTime   // reads 0 after stop()
        recorder.stop()
        reset()
        guard duration >= Self.minimumDuration else {
            recorder.deleteRecording()
            return nil
        }
        return recorder.url
    }

    func cancel() {
        guard let recorder else { return }
        recorder.stop()
        recorder.deleteRecording()
        reset()
    }

    private func reset() {
        meterTask?.cancel()
        meterTask = nil
        recorder = nil
        isRecording = false
    }

    private func startMetering() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.sampleMeter()
                try? await Task.sleep(for: .milliseconds(60))
            }
        }
    }

    private func sampleMeter() {
        guard let recorder, recorder.isRecording else { return }
        recorder.updateMeters()
        let decibels = recorder.averagePower(forChannel: 0)      // -160…0 dBFS
        let level = max(0, min(1, (decibels + 50) / 50))         // speech sits roughly in -50…0
        levels.removeFirst()
        levels.append(level)
        elapsed = recorder.currentTime
    }

    fileprivate func recorderFinished(url: URL, successfully: Bool) {
        // Also fires after stop() and cancel(). By then `recorder` is nil or a newer
        // recording, so the URL check leaves just the 60 s cap.
        guard isRecording, recorder?.url == url else { return }
        reset()
        if successfully { onAutoStop?(url) }
    }
}

extension Recorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor in self.recorderFinished(url: url, successfully: flag) }
    }
}
