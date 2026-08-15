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
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "star") }
            TagsView()
                .tabItem { Label("Tags", systemImage: "tag") }
            BrowseView()
                .tabItem { Label("Accueil", systemImage: "house") }
            TrashView()
                .tabItem { Label("Corbeille", systemImage: "trash") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
        .task { await CategoryStore.shared.loadIfNeeded() }
    }
}
