import SwiftUI

@main
struct WatchGPTApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                // watchgpt://listen, watchgpt://live. Complications and the Smart Stack widget use widgetURL.
                .onOpenURL { url in state.handle(url: url) }
                .task { await state.bootstrap() }
        }
    }
}

/// Consent gate, then a NavigationStack driven by `AppState.path`.
struct RootView: View {
    @Environment(AppState.self) private var state
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var state = state
        Group {
            if state.hasConsented {
                NavigationStack(path: $state.path) {
                    HomeView()
                        .navigationDestination(for: AppState.Screen.self) { screen in
                            switch screen {
                            case .listening: ListeningView()
                            case .answer: AnswerView()
                            case .live: LiveView()
                            case .type: TypeView()
                            case .offline: OfflineView()
                            }
                        }
                }
            } else {
                ConsentView()
            }
        }
        .tint(Theme.amber)
        .sheet(isPresented: $state.showPaywall) { PaywallView() }
        .alert(state.notice ?? "", isPresented: Binding(
            get: { state.notice != nil },
            set: { if !$0 { state.notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        }
        // App Intents (Control, Siri) post here, possibly before this view exists. See also bootstrap().
        .onChange(of: LaunchRouter.shared.pending) { state.consumePendingLaunch() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.appBecameActive() }
        }
    }
}
