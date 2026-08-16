import SwiftUI
import AVFoundation

@main
struct PajApp: App {
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback, options: [])
            try session.setActive(true)
        } catch {
            print("Erreur initialisation AVAudioSession: \(error)")
        }
    }

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
