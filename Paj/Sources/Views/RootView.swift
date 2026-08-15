import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home
    case favorites
    case tags
    case profile
    case settings

    var id: String { rawValue }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: MainTab = .home

    var body: some View {
        Group {
            if !appState.isConfigured {
                SetupView()
            } else if appState.isLocked {
                LockScreenView()
            } else {
                MainTabView(selectedTab: $selectedTab)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: appState.isLocked)
        .animation(.easeInOut(duration: 0.2), value: appState.isConfigured)
        .onChange(of: appState.isLocked) { _, isLocked in
            if !isLocked {
                selectedTab = .home
            }
        }
    }
}

struct MainTabView: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        TabView(selection: $selectedTab) {
            BrowseView()
                .tabItem {
                    Label("Accueil", systemImage: selectedTab == .home ? "house.fill" : "house")
                }
                .tag(MainTab.home)

            FavoritesView()
                .tabItem {
                    Label("Favoris", systemImage: selectedTab == .favorites ? "star.fill" : "star")
                }
                .tag(MainTab.favorites)

            TagsView()
                .tabItem {
                    Label("Tags", systemImage: selectedTab == .tags ? "tag.fill" : "tag")
                }
                .tag(MainTab.tags)

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                }
                .tag(MainTab.profile)

            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape")
                }
                .tag(MainTab.settings)
        }
        .tint(.accentColor)
        .onAppear {
            selectedTab = .home
        }
        .task {
            await CategoryStore.shared.loadIfNeeded()
        }
    }
}
