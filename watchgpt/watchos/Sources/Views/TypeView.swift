import SwiftUI

/// C4: silent input. System keyboard / Scribble / dictation, sent as a text turn with `reply=text`
/// so the speaker stays quiet. There's no Speech framework on watchOS, so system dictation
/// is the only on-watch speech-to-text, and it delivers text only after the user taps Done.
struct TypeView: View {
    @Environment(AppState.self) private var state
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Scribble, dictate or type…", text: $text)
                .submitLabel(.send)
                .onSubmit(send)
            Text("For quiet places: uses the system keyboard and dictation, then sends as a text turn.")
                .font(Theme.small)
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                // Opens the system input sheet directly. The user already tapped Done, so send right away.
                TextFieldLink(prompt: Text("Ask anything")) {
                    Image(systemName: "keyboard")
                } onSubmit: { value in
                    text = value
                    send()
                }
                .buttonStyle(.pill(.secondary))
                .accessibilityLabel("Keyboard or dictation")

                Button("Send", action: send)
                    .buttonStyle(.pill(.primary))
                    .disabled(trimmed.isEmpty)
            }
        }
        .navigationTitle("Type")
        .containerBackground(Color.black, for: .navigation)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send() {
        guard !trimmed.isEmpty else { return }
        state.ask(text: trimmed, reply: .text)
        text = ""
    }
}
