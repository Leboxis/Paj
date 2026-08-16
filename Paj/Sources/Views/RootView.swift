import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case settings
    case tags
    case home
    case favorites
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .settings: return "Réglages"
        case .tags: return "Tags"
        case .home: return "Accueil"
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        }
    }
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

// MARK: - Conteneur d'onglets (barre personnalisée, toutes les vues restent en mémoire)

struct MainTabView: View {
    @Binding var selectedTab: MainTab

    var body: some View {
        ZStack {
            tabContent(SettingsView(), tab: .settings)
            tabContent(TagsView(), tab: .tags)
            tabContent(BrowseView(), tab: .home)
            tabContent(FavoritesView(), tab: .favorites)
            tabContent(ProfileView(), tab: .profile)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            PajTabBar(selectedTab: $selectedTab)
        }
        .tint(.accentColor)
        .onAppear {
            selectedTab = .home
        }
        .task {
            await CategoryStore.shared.loadIfNeeded()
        }
    }

    @ViewBuilder
    private func tabContent<V: View>(_ view: V, tab: MainTab) -> some View {
        let isSelected = selectedTab == tab
        view
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
    }
}

// MARK: - Barre d'onglets du bas

struct PajTabBar: View {
    @Binding var selectedTab: MainTab

    private let inactiveColor = Color(hex: "#7F8AA0") ?? .secondary

    var body: some View {
        HStack(spacing: 0) {
            tabButton(.settings)
            tabButton(.tags)
            tabButton(.home)
            tabButton(.favorites)
            tabButton(.profile)
        }
        .padding(.top, 9)
        .padding(.bottom, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color(.separator).opacity(0.35))
                .frame(height: 0.5)
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let isSelected = selectedTab == tab
        let color = isSelected ? Color.accentColor : inactiveColor
        return Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            VStack(spacing: 4) {
                TabGlyphIcon(kind: tab.glyphKind, size: 23, color: color)
                Text(tab.title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(color)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

extension MainTab {
    var glyphKind: TabGlyphIcon.Kind {
        switch self {
        case .settings: return .sliders
        case .tags: return .tag
        case .home: return .home
        case .favorites: return .star
        case .profile: return .person
        }
    }
}

// MARK: - Icônes dessinées (style minimaliste, trait arrondi)

struct TabGlyphIcon: View {
    enum Kind {
        case home
        case tag
        case star
        case person
        case sliders
    }

    let kind: Kind
    var size: CGFloat = 23
    var color: Color = .accentColor

    var body: some View {
        TabIconPath(kind: kind)
            .stroke(color, style: StrokeStyle(lineWidth: size / 24.0 * 1.8, lineCap: .round, lineJoin: .round))
            .frame(width: size, height: size)
    }
}

/// Chemins définis dans une grille virtuelle de 24×24 puis mis à l'échelle.
struct TabIconPath: Shape {
    let kind: TabGlyphIcon.Kind

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24.0
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * s, y: rect.minY + y * s)
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect {
            CGRect(x: rect.minX + x * s, y: rect.minY + y * s, width: w * s, height: h * s)
        }

        var p = Path()

        switch kind {
        case .home:
            // Toit
            p.move(to: pt(3.6, 12.0))
            p.addLine(to: pt(12, 4.6))
            p.addLine(to: pt(20.4, 12.0))
            // Corps
            p.addRoundedRect(in: box(6.6, 10.4, 10.8, 8.6), cornerSize: CGSize(width: 2.6 * s, height: 2.6 * s))
            // Porte
            p.addRoundedRect(in: box(10.3, 14.8, 3.4, 4.2), cornerSize: CGSize(width: 1.3 * s, height: 1.3 * s))

        case .tag:
            // Étiquette inclinée (pointe en haut à droite)
            p.move(to: pt(5.42, 14.60))
            p.addLine(to: pt(11.8, 8.3))   // bord supérieur
            p.addLine(to: pt(17.7, 6.3))   // pointe
            p.addLine(to: pt(15.7, 12.2))  // bord inférieur
            p.addLine(to: pt(9.40, 18.58)) // avant coin bas-gauche
            p.addQuadCurve(to: pt(6.59, 18.59), control: pt(8.0, 20.0))
            p.addLine(to: pt(5.41, 17.41)) // avant coin gauche
            p.addQuadCurve(to: pt(5.42, 14.60), control: pt(4.0, 16.0))
            p.closeSubpath()
            // Trou de l'étiquette
            p.addEllipse(in: box(7.45, 14.45, 2.1, 2.1))

        case .star:
            p.move(to: pt(12, 3.9))
            p.addLine(to: pt(14.2, 9.4))
            p.addLine(to: pt(20.1, 9.8))
            p.addLine(to: pt(15.5, 13.5))
            p.addLine(to: pt(17.0, 19.3))
            p.addLine(to: pt(12, 16.1))
            p.addLine(to: pt(7.0, 19.3))
            p.addLine(to: pt(8.5, 13.5))
            p.addLine(to: pt(3.9, 9.8))
            p.addLine(to: pt(9.8, 9.4))
            p.closeSubpath()

        case .person:
            // Tête
            p.addEllipse(in: box(8.8, 4.6, 6.4, 6.4))
            // Épaules
            p.move(to: pt(5.5, 19.6))
            p.addLine(to: pt(5.5, 17.5))
            p.addQuadCurve(to: pt(12, 12.3), control: pt(5.5, 12.3))
            p.addQuadCurve(to: pt(18.5, 17.5), control: pt(18.5, 12.3))
            p.addLine(to: pt(18.5, 19.6))

        case .sliders:
            // Rangée 1
            p.move(to: pt(4.6, 6.6))
            p.addLine(to: pt(11.8, 6.6))
            p.move(to: pt(17.4, 6.6))
            p.addLine(to: pt(19.4, 6.6))
            p.addEllipse(in: box(12.6, 4.6, 4.0, 4.0))
            // Rangée 2
            p.move(to: pt(4.6, 12.0))
            p.addLine(to: pt(6.6, 12.0))
            p.move(to: pt(12.2, 12.0))
            p.addLine(to: pt(19.4, 12.0))
            p.addEllipse(in: box(7.4, 10.0, 4.0, 4.0))
            // Rangée 3
            p.move(to: pt(4.6, 17.4))
            p.addLine(to: pt(9.8, 17.4))
            p.move(to: pt(15.4, 17.4))
            p.addLine(to: pt(19.4, 17.4))
            p.addEllipse(in: box(10.6, 15.4, 4.0, 4.0))
        }

        return p
    }
}
