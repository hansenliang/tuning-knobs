import SwiftUI

/// C2: one tier, bought with StoreKit on the watch. Shown on `402 quota_exceeded`.
struct PaywallView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let store = state.store
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(store.product?.displayPrice ?? "$9.99")
                            .font(.system(size: 26, weight: .bold))
                        Text("/ month")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                    // Copy is from the mockup. Keep it in sync with the server's pro limits (server/src/config.ts).
                    Text("Unlimited asks\n60 min of Live per month\nBest models, no ads")
                        .font(Theme.small)
                        .foregroundStyle(Theme.bright)
                    Text(store.trialLine)
                        .font(Theme.small)
                        .foregroundStyle(Theme.dim)
                    if let resetsAt = state.paywallResetsAt {
                        Text("Free asks return at \(resetsAt.formatted(date: .omitted, time: .shortened)).")
                            .font(Theme.small)
                            .foregroundStyle(Theme.dim)
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(Theme.small)
                            .foregroundStyle(Theme.red)
                    }

                    Button {
                        Task { await store.purchase() }
                    } label: {
                        if store.isPurchasing {
                            ProgressView()
                        } else {
                            Text(store.isEligibleForTrial ? "Start trial" : "Subscribe")
                        }
                    }
                    .buttonStyle(.pill(.primary))
                    .disabled(store.isPurchasing || store.product == nil)
                    .padding(.top, 4)

                    Button("Restore purchases") { Task { await store.restore() } }
                        .buttonStyle(.plain)
                        .font(Theme.small)
                        .foregroundStyle(Theme.dim)

                    // App Review 3.1.2: subscriptions need working Terms and Privacy links.
                    HStack(spacing: 12) {
                        Link("Terms", destination: AppConfig.termsURL)
                        Link("Privacy", destination: AppConfig.privacyURL)
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("Keep talking")
            .containerBackground(Color.black, for: .navigation)
        }
        .task {
            if store.product == nil { await store.loadProduct() }
        }
    }
}
