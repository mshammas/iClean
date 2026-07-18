import SwiftUI

/// App entry point. Owns the single shared `AppState` and hands it to the view tree.
@main
struct iCleanApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}
