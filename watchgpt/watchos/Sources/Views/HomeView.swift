import SwiftUI

/// A1: the mic is the whole home screen. Below it, the Live pill and a peek at the last answer.
struct HomeView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        GeometryReader { proxy in
            let micDiameter = min(104, proxy.size.height * 0.5)
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Button { state.startListening() } label: {
                    MicHero(diameter: micDiameter)
                }
                .buttonStyle(.plain)
                .handGestureShortcut(.primaryAction)   // D4: double tap to ask
                .accessibilityLabel("Ask")

                Button { state.startLive() } label: { LivePill() }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Start a Live conversation")
                Spacer(minLength: 0)

                if let last = state.turns.lastAnswer {
                    Button { state.showThread() } label: {
                        Text(peek(last))
                            .font(Theme.small)
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Open the thread")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Ask")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { state.showTyping() } label: { Image(systemName: "keyboard") }
                    .accessibilityLabel("Type a question")
            }
        }
        .containerBackground(Color.black, for: .navigation)
    }

    /// "Garlic shrimp, 15 min · 2m ago"
    private func peek(_ message: ChatMessage) -> String {
        let firstSentence = message.text.split(whereSeparator: { ".!?".contains($0) }).first.map(String.init) ?? message.text
        let when = message.at.formatted(.relative(presentation: .numeric, unitsStyle: .narrow))
        return "\(firstSentence.prefix(28)) · \(when)"
    }
}
