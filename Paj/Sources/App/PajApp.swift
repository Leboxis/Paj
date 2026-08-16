import SwiftUI

@main
struct PajApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .tint(.accentColor)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        appState.lock()
                    }
                }
        }
    }
}
