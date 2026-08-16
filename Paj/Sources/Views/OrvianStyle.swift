import SwiftUI

/// Palette et surfaces reprises du thème sombre d'Orvian.
enum OrvianStyle {
    static let background = Color(hex: "#080C14") ?? .black
    static let cardBackground = Color(hex: "#0B111B")?.opacity(0.88) ?? Color.black.opacity(0.88)
    static let tertiaryBackground = Color(hex: "#1B2435") ?? Color(.systemGray6)
    static let textSecondary = Color(hex: "#B2BDCF") ?? .secondary
    static let textTertiary = Color(hex: "#7F8AA0") ?? .secondary
    static let accent = Color(hex: "#3B82F6") ?? .blue
    static let accentSecondary = Color(hex: "#14B8A6") ?? .teal
    static let border = Color.white.opacity(0.10)
    static let shadow = Color.black.opacity(0.34)

    static let cardRadius: CGFloat = 14
    static let thumbnailRadius: CGFloat = 12
}

struct OrvianGlassBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    OrvianStyle.background
                    RadialGradient(
                        colors: [OrvianStyle.accent.opacity(0.16), .clear],
                        center: .topLeading,
                        startRadius: 0,
                        endRadius: 280
                    )
                    RadialGradient(
                        colors: [OrvianStyle.accentSecondary.opacity(0.10), .clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 240
                    )
                }
                .ignoresSafeArea()
            )
    }
}

extension View {
    func orvianGlassBackground() -> some View {
        modifier(OrvianGlassBackground())
    }
}
