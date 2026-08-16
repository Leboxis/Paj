import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case settings
    case tags
    case home
    case favorites
    case profile

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
            SettingsView()
                .tabItem {
                    Label("Réglages", systemImage: "slider.horizontal.3")
                }
                .tag(MainTab.settings)

            TagsView()
                .tabItem {
                    Label("Tags", systemImage: selectedTab == .tags ? "tag.2.fill" : "tag.2")
                }
                .tag(MainTab.tags)

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

            ProfileView()
                .tabItem {
                    Label("Profil", systemImage: selectedTab == .profile ? "person.crop.circle.fill" : "person.crop.circle")
                }
                .tag(MainTab.profile)
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
