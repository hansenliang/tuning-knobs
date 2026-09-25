import AVFoundation
import os

enum LiveAudioError: Error {
    case noMicrophone
    case unsupportedFormat
}

/// Full-duplex audio for Live mode on one AVAudioEngine. Voice-processing echo
/// cancellation needs the mic and the speaker on the same engine.
///
/// - Up: input tap → AVAudioConverter → 24 kHz mono PCM16 LE → 100 ms frames (4,800 bytes) → `onFrame`.
/// - Down: PCM16 24 kHz from the socket → Float32 buffers → AVAudioPlayerNode.
///
/// Threading: `onFrame` runs on the tap thread. `enqueuePlayback`/`flushPlayback` are called
/// from the main actor. Shared mutable state sits behind the two locks below.
/// Set the callbacks once, before `start()`.
final class LiveAudioIO: @unchecked Sendable {
    static let sampleRate: Double = 24_000
    static let frameBytes = 4_800   // 100 ms × 24,000 Hz × 2 bytes

    /// Tap thread. `level` is the frame's RMS, 0…1.
    var onFrame: (@Sendable (_ frame: Data, _ level: Float) -> Void)?
    /// Every scheduled buffer has played (or been flushed).
    var onPlaybackDrained: (@Sendable () -> Void)?
    /// Route change (AirPods on/off): the input format may differ, so the caller should restart().
    var onConfigurationChange: (@Sendable () -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let wireFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                                           channels: 1, interleaved: true)!
    private let playbackFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                               channels: 1, interleaved: false)!

    private struct CaptureState {
        var converter: AVAudioConverter?
        var pending = Data()
    }
    private let capture = OSAllocatedUnfairLock(uncheckedState: CaptureState())

    private struct PlaybackState: Sendable {
        var generation = 0   // bumped by flush; stale completion handlers are ignored
        var queued = 0
    }
    private let playback = OSAllocatedUnfairLock(initialState: PlaybackState())

    private var voiceProcessingEnabled = false
    private var configObserver: NSObjectProtocol?

    init() {
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.onConfigurationChange?()
        }
    }

    deinit {
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
    }

    /// Call only after the audio session is active (category .playAndRecord).
    func start() throws {
        let input = engine.inputNode

        // Must be set while the engine is stopped and before reading formats. Whether this
        // actually cancels the watch speaker's echo is UNVERIFIED on hardware. The server-side
        // VAD barge-in is the backstop.
        if !voiceProcessingEnabled {
            do {
                try input.setVoiceProcessingEnabled(true)
                voiceProcessingEnabled = true
            } catch {
                Log.audio.error("Voice processing unavailable: \(error.localizedDescription)")
            }
        }

        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw LiveAudioError.noMicrophone }
        guard let converter = AVAudioConverter(from: inputFormat, to: wireFormat) else {
            throw LiveAudioError.unsupportedFormat
        }
        converter.downmix = true   // voice processing may present more than one input channel
        capture.withLockUnchecked { state in
            state.converter = converter
            state.pending.removeAll(keepingCapacity: true)
        }

        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: playbackFormat)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2_048, format: inputFormat) { [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
        player.play()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        playback.withLock { state in
            state.generation += 1
            state.queued = 0
        }
        player.stop()
        engine.stop()
    }

    /// After an interruption or route change.
    func restart() throws {
        stop()
        try start()
    }

    // MARK: Capture (tap thread)

    private func process(_ buffer: AVAudioPCMBuffer) {
        let frames: [Data] = capture.withLockUnchecked { state in
            guard let converter = state.converter else { return [] }
            let ratio = Self.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 32
            guard let converted = AVAudioPCMBuffer(pcmFormat: wireFormat, frameCapacity: capacity) else { return [] }

            // Feed exactly this one buffer. `.noDataNow` (not `.endOfStream`) keeps the
            // resampler's history, so the next tap callback continues seamlessly.
            // A reference box, not a captured `var`: if the SDK marks the input block @Sendable,
            // mutating a captured var is a hard error even in Swift 5 mode.
            let fed = FedFlag()
            var error: NSError?
            let status = converter.convert(to: converted, error: &error) { _, inputStatus in
                if fed.value {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                fed.value = true
                inputStatus.pointee = .haveData
                return buffer
            }
            guard status != .error, converted.frameLength > 0,
                  let samples = converted.int16ChannelData?[0] else {
                if let error { Log.audio.error("Convert failed: \(error.localizedDescription)") }
                return []
            }
            state.pending.append(Data(bytes: samples, count: Int(converted.frameLength) * 2))

            var out: [Data] = []
            while state.pending.count >= Self.frameBytes {
                out.append(Data(state.pending.prefix(Self.frameBytes)))
                state.pending.removeFirst(Self.frameBytes)
            }
            return out
        }
        for frame in frames {
            onFrame?(frame, Self.rms(frame))
        }
    }

    // MARK: Playback

    /// Schedules PCM16 LE mono 24 kHz. Returns the chunk's RMS level for the orb.
    @discardableResult
    func enqueuePlayback(_ pcm: Data) -> Float {
        let frameCount = pcm.count / 2
        guard engine.isRunning, frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: AVAudioFrameCount(frameCount)),
              let out = buffer.floatChannelData?[0] else { return 0 }
        buffer.frameLength = AVAudioFrameCount(frameCount)

        var sumSquares: Float = 0
        pcm.withUnsafeBytes { raw in
            for i in 0..<frameCount {
                // loadUnaligned: socket payloads aren't guaranteed to be 2-byte aligned.
                let sample = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32_768
                out[i] = sample
                sumSquares += sample * sample
            }
        }

        let generation = playback.withLock { state -> Int in
            state.queued += 1
            return state.generation
        }
        player.scheduleBuffer(buffer) { [weak self] in
            self?.bufferFinished(generation: generation)
        }
        if !player.isPlaying { player.play() }
        return (sumSquares / Float(frameCount)).squareRoot()
    }

    /// Barge-in: drop everything scheduled, right now.
    func flushPlayback() {
        playback.withLock { state in
            state.generation += 1
            state.queued = 0
        }
        player.stop()   // runs the pending completion handlers, which are now stale
        if engine.isRunning { player.play() }
        onPlaybackDrained?()
    }

    private func bufferFinished(generation: Int) {
        let drained = playback.withLock { state -> Bool in
            guard state.generation == generation else { return false }
            state.queued -= 1
            return state.queued == 0
        }
        if drained { onPlaybackDrained?() }
    }

    /// Used only synchronously inside one `convert` call.
    private final class FedFlag: @unchecked Sendable {
        var value = false
    }

    private static func rms(_ frame: Data) -> Float {
        let count = frame.count / 2
        guard count > 0 else { return 0 }
        var sum: Float = 0
        frame.withUnsafeBytes { raw in
            for i in 0..<count {
                let sample = Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: i * 2, as: Int16.self))) / 32_768
                sum += sample * sample
            }
        }
        return (sum / Float(count)).squareRoot()
    }
}
