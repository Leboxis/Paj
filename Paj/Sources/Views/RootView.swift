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
            SettingsView()
                .tabItem { Label("Réglages", image: "tab-settings") }
            TagsView()
                .tabItem { Label("Tags", image: "tab-tags") }
            BrowseView()
                .tabItem { Label("Accueil", image: "tab-home") }
            FavoritesView()
                .tabItem { Label("Favoris", image: "tab-favorites") }
            ProfileView()
                .tabItem { Label("Profil", image: "tab-profile") }
        }
        .task { await CategoryStore.shared.loadIfNeeded() }
    }
}
