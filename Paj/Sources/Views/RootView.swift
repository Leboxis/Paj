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
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .settings:
                    SettingsView()
                case .tags:
                    TagsView()
                case .home:
                    BrowseView()
                case .favorites:
                    FavoritesView()
                case .profile:
                    ProfileView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaPadding(.bottom, 78)

            OrvianBottomNav(selectedTab: $selectedTab)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .orvianGlassBackground()
        .preferredColorScheme(.dark)
        .onAppear {
            selectedTab = .home
        }
        .task {
            await CategoryStore.shared.loadIfNeeded()
        }
    }
}

/// Barre flottante en pilule, avec les mêmes icônes Lucide et le même ordre
/// qu'Orvian : Réglages, Tags, Accueil, Favoris, Profil.
private struct OrvianBottomNav: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        HStack(spacing: 1) {
            ForEach(MainTab.allCases) { tab in
                let isSelected = selectedTab == tab
                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.orvianSystemImage)
                            .font(.system(size: 21, weight: isSelected ? .semibold : .regular))
                        Text(tab.label)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.68))
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(isSelected ? OrvianStyle.accent.opacity(0.18) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 6)
        .frame(maxWidth: 560)
        .background(
            LinearGradient(
                colors: [
                    Color(hex: "#172132")?.opacity(0.92) ?? Color.black.opacity(0.92),
                    Color(hex: "#101827")?.opacity(0.96) ?? Color.black.opacity(0.96)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
        .clipShape(Capsule())
        .shadow(color: OrvianStyle.shadow, radius: 12, x: 0, y: 6)
    }
}

private extension MainTab {
    var label: String {
        switch self {
        case .settings: return "Réglages"
        case .tags: return "Tags"
        case .home: return "Accueil"
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        }
    }

    /// Équivalents SF Symbols des icônes Lucide utilisées par Orvian.
    var orvianSystemImage: String {
        switch self {
        case .settings: return "slider.horizontal.3"
        case .tags: return "tag.2"
        case .home: return "house"
        case .favorites: return "star"
        case .profile: return "person.crop.circle"
        }
    }
}
