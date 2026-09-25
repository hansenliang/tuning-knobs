import SwiftUI

/// A2 (and D3, when opened by the Action button): recording with live meter bars.
/// Tap anywhere or Send to send, ✕ to cancel, double tap sends.
struct ListeningView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let recorder = state.recorder
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            WaveformBars(levels: recorder.levels, maxHeight: 64)
            Text("Tap to send · wrist down cancels")
                .font(Theme.small)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Button { state.cancelRecording() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.pill(.destructive, round: true))
                    .accessibilityLabel("Cancel")
                Button("Send") { state.sendRecording() }
                    .buttonStyle(.pill(.primary))
                    .handGestureShortcut(.primaryAction)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { state.sendRecording() }
        .navigationTitle("Listening")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text(TimeText.minutesSeconds(Int(recorder.elapsed)))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
        }
        .containerBackground(Color.black, for: .navigation)
        .onChange(of: scenePhase) { _, phase in
            // A2: "wrist down cancels". The 1 s guard skips the brief inactive phase at launch
            // from a Control or complication, before the user has said anything.
            if phase != .active, recorder.isRecording, recorder.elapsed > 1 {
                state.cancelRecording()
            }
        }
    }
}
