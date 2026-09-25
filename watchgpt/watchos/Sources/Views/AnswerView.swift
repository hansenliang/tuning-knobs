import SwiftUI

/// A3/A4: the thread. The user bubble shows first (the transcript), then streaming reply
/// text with a cursor, spoken sentence by sentence. Stop cuts it off, the mic asks a follow-up.
struct AnswerView: View {
    @Environment(AppState.self) private var state
    private static let bottomID = "bottom"

    var body: some View {
        let turns = state.turns
        let speaking = state.player.isPlaying
        VStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(turns.recentMessages) { message in
                            MessageRow(message: message, streaming: message.id == turns.streamingMessageID)
                        }
                        if turns.isAwaitingReply {
                            TypingDots()
                        }
                        if case .failed(let text) = turns.status {
                            Label(text, systemImage: "exclamationmark.circle")
                                .font(Theme.small)
                                .foregroundStyle(Theme.red)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                .onChange(of: turns.scrollKey) {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                }
            }

            HStack(spacing: 8) {
                Button { state.stopAnswer() } label: { Image(systemName: "stop.fill") }
                    .buttonStyle(.pill(.secondary, round: true))
                    .disabled(!turns.isBusy && !speaking)
                    .accessibilityLabel("Stop")
                Button { state.startListening() } label: { Image(systemName: "mic.fill") }
                    .buttonStyle(.pill(.primary))
                    .handGestureShortcut(.primaryAction)   // D4: double tap to reply
                    .accessibilityLabel("Ask a follow-up")
            }
        }
        .navigationTitle(speaking ? "Answer" : "Ask")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if speaking { SpeakingBars() }
            }
        }
        .containerBackground(Color.black, for: .navigation)
    }
}

private struct MessageRow: View {
    let message: ChatMessage
    let streaming: Bool

    var body: some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 20)
                Text(verbatim: message.text.isEmpty ? "…" : message.text)
                    .font(Theme.bubbleFont)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Theme.bubble, in: UnevenRoundedRectangle(
                        topLeadingRadius: 16, bottomLeadingRadius: 16,
                        bottomTrailingRadius: 4, topTrailingRadius: 16))
            }
        case .assistant:
            if streaming {
                // Blinking amber cursor at the end of the text (A4).
                TimelineView(.periodic(from: .now, by: 0.5)) { context in
                    let on = Int(context.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                    Text("\(Text(verbatim: message.text))\(Text(verbatim: " ▍").foregroundStyle(on ? Theme.amber : Color.clear))")
                        .font(Theme.body)
                }
            } else {
                Text(verbatim: message.text)
                    .font(Theme.body)
            }
        }
    }
}
