import SwiftUI

/// A1 hero button: amber gradient disc, mic glyph, faint 7 pt halo.
struct MicHero: View {
    var diameter: CGFloat = 104

    var body: some View {
        ZStack {
            Circle().fill(Theme.micGradient(diameter: diameter))
            Image(systemName: "mic.fill")
                .font(.system(size: diameter * 0.38, weight: .semibold))
                .foregroundStyle(Theme.micGlyph)
        }
        .frame(width: diameter, height: diameter)
        .padding(7)
        .background(Circle().fill(Theme.amber.opacity(0.13)))
    }
}

/// A1 "● Live" pill.
struct LivePill: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Theme.amber).frame(width: 7, height: 7)
            Text("Live")
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
        .background(Theme.card, in: Capsule())
    }
}

/// A2 waveform: one bar per recent meter sample.
struct WaveformBars: View {
    let levels: [Float]
    var maxHeight: CGFloat = 70

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.amber)
                    .frame(width: 6, height: max(8, CGFloat(level) * maxHeight))
            }
        }
        .frame(height: maxHeight)
        .animation(.linear(duration: 0.08), value: levels)
        .accessibilityHidden(true)
    }
}

/// A4 title-bar "speaking" glyph: three bouncing bars.
struct SpeakingBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * 2 * .pi / 0.8 + Double(i) * 1.6
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.amber)
                        .frame(width: 3, height: 12 * (0.45 + 0.55 * abs(sin(phase))))
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
        .accessibilityLabel("Speaking")
    }
}

/// A3 "thinking" dots.
struct TypingDots: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t / 1.2 - Double(i) * 0.125).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .fill(Theme.dim)
                        .frame(width: 9, height: 9)
                        .opacity(phase < 0.4 ? 0.3 + 0.7 * (phase / 0.4) : 1 - 0.7 * ((phase - 0.4) / 0.6))
                }
            }
            .padding(.vertical, 10)
        }
        .accessibilityLabel("Thinking")
    }
}

/// B1–B3 orb. "breathe" while listening, "talk" while speaking, desaturated when muted.
struct OrbView: View {
    enum Mode { case listening, speaking, muted, waiting }

    let mode: Mode
    let level: Float
    let diameter: CGFloat
    /// False in Always On (isLuminanceReduced): draw a still orb.
    var animated = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animated || mode == .muted)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            Circle()
                .fill(Theme.orbGradient(diameter: diameter))
                .frame(width: diameter, height: diameter)
                .scaleEffect(animated ? scale(at: t) : 1)
                .shadow(color: mode == .muted ? .clear : Theme.amber.opacity(0.28), radius: 20)
                .saturation(mode == .muted ? 0.2 : 1)
                .brightness(mode == .muted ? -0.35 : 0)
                .opacity(mode == .waiting && animated ? 0.6 + 0.3 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.6)) : 1)
        }
        .frame(width: diameter * 1.15, height: diameter * 1.15)
        .animation(.easeInOut(duration: 0.3), value: diameter)
    }

    private func scale(at t: TimeInterval) -> CGFloat {
        switch mode {
        case .listening, .waiting:
            // @keyframes breathe: 3.2 s period, peaks at +6 %
            return 1 + 0.03 * (1 - cos(t * 2 * .pi / 3.2))
        case .speaking:
            // @keyframes talk: 0.97 ↔ 1.10 every 0.5 s, nudged by output loudness
            let base = 0.97 + 0.065 * (1 - cos(t * 2 * .pi / 1.0))
            return base + min(0.08, CGFloat(level) * 0.3)
        case .muted:
            return 1
        }
    }
}

/// B4 minutes meter.
struct Meter: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.faint)
                Capsule().fill(Theme.amber)
                    .frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 4)
    }
}

enum TimeText {
    /// 402 → "6:42", 3725 → "62:05"
    static func minutesSeconds(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
