import AVFoundation
import Observation

/// Plays `audio.segment` files (standalone MP3/AAC/WAV sentences) strictly in `seq` order,
/// one AVAudioPlayer at a time. Speech starts after about one sentence of LLM output
/// without a streaming decoder. Mirrors `makePlayer()` in server/public/index.html.
@MainActor @Observable
final class SegmentPlayer: NSObject {
    private(set) var isPlaying = false

    /// The queue ran dry after playing something. More segments may still arrive.
    @ObservationIgnored var onDrained: (() -> Void)?

    @ObservationIgnored private var pending: [Int: AudioSegment] = [:]
    @ObservationIgnored private var skipped: Set<Int> = []
    @ObservationIgnored private var nextSeq = 0
    @ObservationIgnored private var current: AVAudioPlayer?
    @ObservationIgnored private var accepting = true

    /// Starts a new turn: `seq` restarts at 0.
    func reset() {
        stop()
        nextSeq = 0
        accepting = true
    }

    func enqueue(_ segment: AudioSegment) {
        guard accepting, segment.seq >= nextSeq else { return }
        pending[segment.seq] = segment
        playNextIfIdle()
    }

    /// The server couldn't synthesize this sentence (`audio.error`). Don't stall the queue on it.
    func skip(seq: Int) {
        guard seq >= nextSeq else { return }
        skipped.insert(seq)
        playNextIfIdle()
    }

    /// Stop button: cut off now and drop everything queued until the next reset().
    func stop() {
        accepting = false
        current?.stop()
        current = nil
        pending.removeAll()
        skipped.removeAll()
        isPlaying = false
    }

    private func playNextIfIdle() {
        guard current == nil else { return }
        while skipped.remove(nextSeq) != nil { nextSeq += 1 }
        guard let segment = pending.removeValue(forKey: nextSeq) else {
            if isPlaying {
                isPlaying = false
                onDrained?()
            }
            return
        }
        nextSeq += 1
        do {
            let player = try AVAudioPlayer(data: segment.data, fileTypeHint: Self.fileTypeHint(segment.format))
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw CocoaError(.fileReadCorruptFile) }
            current = player
            isPlaying = true
        } catch {
            Log.audio.error("Skipping segment \(segment.seq): \(error.localizedDescription)")
            playNextIfIdle()
        }
    }

    fileprivate func playerFinished(_ id: ObjectIdentifier) {
        guard let current, ObjectIdentifier(current) == id else { return }
        self.current = nil
        playNextIfIdle()
    }

    private static func fileTypeHint(_ format: String) -> String? {
        switch format.lowercased() {
        case "mp3": AVFileType.mp3.rawValue
        case "wav": AVFileType.wav.rawValue
        case "aac": "public.aac-audio"
        default: nil
        }
    }
}

extension SegmentPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id) }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.playerFinished(id) }
    }
}
