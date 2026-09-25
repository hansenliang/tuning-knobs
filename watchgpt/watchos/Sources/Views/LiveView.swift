import SwiftUI

/// B1 listening · B2 speaking · B3 muted · B4 summary.
/// Top right shows the minutes left, not the wall clock.
struct LiveView: View {
    @Environment(AppState.self) private var state
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        let live = state.live
        Group {
            if live.phase == .ended {
                LiveSummaryView()
            } else {
                session(live)
            }
        }
        .navigationBarBackButtonHidden(true)
        .containerBackground(Color.black, for: .navigation)
    }

    private func session(_ live: LiveSession) -> some View {
        GeometryReader { proxy in
            let base = min(120, proxy.size.height * 0.55)
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Button { orbTapped(live) } label: {
                    OrbView(mode: orbMode(live),
                            level: live.phase == .speaking ? live.outputLevel : live.micLevel,
                            diameter: orbDiameter(live, base: base),
                            animated: !isLuminanceReduced)
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)   // double tap: interrupt / unmute / resume
                .accessibilityLabel(orbLabel(live))

                Text(caption(live))
                    .font(live.phase == .speaking || !live.assistantCaption.isEmpty ? Theme.caption : Theme.small)
                    .foregroundStyle(captionIsHint(live) ? Theme.dim : .white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(minHeight: 34)
                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Button { state.endLive() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.pill(.destructive))
                        .accessibilityLabel("End Live")
                    Button { live.toggleMute() } label: {
                        Image(systemName: live.isMuted ? "mic.fill" : "mic.slash.fill")
                    }
                    .buttonStyle(.pill(live.isMuted ? .primary : .secondary))
                    .accessibilityLabel(live.isMuted ? "Unmute" : "Mute")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle(live.isMuted ? "Live · muted" : "Live")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let left = live.secondsLeft {
                    Text(TimeText.minutesSeconds(left))
                        .monospacedDigit()
                        .accessibilityLabel("\(left / 60) minutes left")
                }
            }
        }
    }

    // MARK: Mapping LiveSession state to the mockups

    private func orbMode(_ live: LiveSession) -> OrbView.Mode {
        if live.isMuted { return .muted }
        switch live.phase {
        case .speaking: return .speaking
        case .listening: return .listening
        default: return .waiting
        }
    }

    private func orbDiameter(_ live: LiveSession, base: CGFloat) -> CGFloat {
        // B1 120 · B2 104 · B3 96 (at 46 mm)
        if live.isMuted { return base * 0.8 }
        return live.phase == .speaking ? base * 0.87 : base
    }

    private func orbTapped(_ live: LiveSession) {
        if live.phase == .interrupted {
            Task { await live.resumeAfterInterruption() }
        } else if live.isMuted {
            live.toggleMute()
        } else {
            live.interruptReply()
        }
    }

    private func caption(_ live: LiveSession) -> String {
        switch live.phase {
        case .idle, .connecting: return "Connecting…"
        case .reconnecting: return "Reconnecting…"
        case .interrupted: return "Paused. Tap the orb to resume."
        case .ended: return ""
        case .listening, .speaking:
            if live.isMuted { return "Mic off. Tap the orb to talk." }
            if !live.assistantCaption.isEmpty { return live.assistantCaption }
            if !live.userCaption.isEmpty { return "“\(live.userCaption)”" }
            return "Listening…"
        }
    }

    private func captionIsHint(_ live: LiveSession) -> Bool {
        live.isMuted || live.assistantCaption.isEmpty && live.userCaption.isEmpty
            || live.phase == .interrupted || live.phase == .reconnecting || live.phase == .connecting
    }

    private func orbLabel(_ live: LiveSession) -> String {
        switch live.phase {
        case .interrupted: "Resume"
        case .speaking: "Interrupt"
        default: live.isMuted ? "Unmute" : "Live"
        }
    }
}

/// B4: how long you talked, what's left, and a note that it's in the thread.
struct LiveSummaryView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let live = state.live
        let left = state.liveSecondsLeftThisMonth ?? live.secondsLeft
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text(TimeText.minutesSeconds(live.secondsUsed))
                    .font(.system(size: 30, weight: .bold))
                    .monospacedDigit()
                Text(left.map { "talked · \($0 / 60) min left today" } ?? "talked")
                    .font(Theme.small)
                    .foregroundStyle(Theme.dim)
                if let left, live.secondsUsed + left > 0 {
                    Meter(fraction: Double(live.secondsUsed) / Double(live.secondsUsed + left))
                }
                Text("Saved to your thread.")
                    .font(Theme.small)
                    .foregroundStyle(Theme.dim)
                if let message = live.endReason?.message {
                    Text(message)
                        .font(Theme.small)
                        .foregroundStyle(Theme.amber)
                }
                if live.endReason == .quotaExceeded, state.plan != "pro" {
                    Button("See Pro") { state.presentPaywall(resetsAt: nil) }
                        .buttonStyle(.pill(.secondary))
                }
                Button("Done") { state.finishLive() }
                    .buttonStyle(.pill(.primary))
                    .handGestureShortcut(.primaryAction)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Live ended")
        .task { await state.refreshAccount() }
    }
}
