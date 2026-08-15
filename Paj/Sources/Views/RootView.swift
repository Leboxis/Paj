import SwiftUI

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if !appState.isConfigured {
                SetupView()
            } else if appState.isLocked {
                LockScreenView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isLocked)
        .animation(.easeInOut(duration: 0.2), value: appState.isConfigured)
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            BrowseView()
                .tabItem { Label("Parcourir", systemImage: "folder") }
            MediaView()
                .tabItem { Label("Médias", systemImage: "photo.on.rectangle.angled") }
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "star") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
