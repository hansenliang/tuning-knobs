import SwiftUI

/// C3: the recording is saved on disk and retried automatically.
struct OfflineView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let offline = state.offline
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: "wifi.slash")
                .font(.system(size: 30))
                .foregroundStyle(Theme.dim)
            Text("No connection")
                .font(.system(size: 16, weight: .semibold))
            Text("Your question is saved. It sends when LTE or Wi-Fi is back.")
                .font(Theme.small)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            if offline.items.count > 1 {
                Text("\(offline.items.count) questions waiting")
                    .font(Theme.small)
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 0)
            Button {
                Task { await state.retryOfflineNow() }
            } label: {
                if offline.isRetrying { ProgressView() } else { Text("Retry now") }
            }
            .buttonStyle(.pill(.primary))
            .disabled(offline.isRetrying)
        }
        .navigationTitle("Ask")
        .containerBackground(Color.black, for: .navigation)
        .onChange(of: offline.items.isEmpty) { _, isEmpty in
            if isEmpty { state.offlineQueueDrained() }
        }
    }
}
