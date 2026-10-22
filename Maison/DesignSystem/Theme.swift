import SwiftUI

/// Design tokens from the Figma "Maison" collection (light and dark modes live in the asset catalog).
enum Theme {
    static let background = Color("SurfaceBackground")
    static let card = Color("SurfaceCard")
    static let pill = Color("SurfacePill")
    static let pillActive = Color("SurfacePillActive")
    static let textOnPillActive = Color("TextOnPillActive")
    static let separator = Color("Separator")
    static let gaugeTrack = Color("GaugeTrack")
    static let trendUpBackground = Color("TrendUpBackground")
    static let trendDownBackground = Color("TrendDownBackground")
    static let cardBorder = Color("CardBorder")

    /// Marks text written on the iPhone by the language model (the "Symbole/Génération" sparkles).
    static let generated = LinearGradient(
        colors: [Color(red: 1, green: 0.6, blue: 0.15), Color(red: 0.95, green: 0.25, blue: 0.5), Color(red: 0.42, green: 0.36, blue: 1)],
        startPoint: .bottomLeading,
        endPoint: .topTrailing
    )

    static let cardRadius: CGFloat = 26
    static let rowRadius: CGFloat = 20
    static let tileRadius: CGFloat = 22
    static let screenPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 14
}

extension Font {
    // Text styles from the "Arrondi" set.
    static let roundedHeadline = Font.system(.headline, design: .rounded) // 17 semibold
    static let roundedBody = Font.system(.body, design: .rounded) // 17 regular
    static let roundedSubheadline = Font.system(.subheadline, design: .rounded) // 15 regular
    static let roundedSubheadlineEmphasized = Font.system(.subheadline, design: .rounded).weight(.semibold)
    static let roundedFootnote = Font.system(.footnote, design: .rounded) // 13 regular
    static let roundedFootnoteEmphasized = Font.system(.footnote, design: .rounded).weight(.semibold)
    static let roundedTitle3 = Font.system(.title3, design: .rounded).weight(.semibold) // 20 semibold
}

/// The "Chiffres" number styles: a large semibold value followed by a lighter unit.
enum NumberSize {
    case medium // 34 / 20
    case large // 42 / 18 (hero ring)
    case xLarge // 56 / 30

    var value: Font {
        switch self {
        case .medium: .system(size: 34, weight: .semibold, design: .rounded)
        case .large: .system(size: 42, weight: .semibold, design: .rounded)
        case .xLarge: .system(size: 56, weight: .semibold, design: .rounded)
        }
    }

    var unit: Font {
        switch self {
        case .medium: .system(size: 20, weight: .medium, design: .rounded)
        case .large: .system(size: 18, weight: .medium, design: .rounded)
        case .xLarge: .system(size: 30, weight: .medium, design: .rounded)
        }
    }
}

extension View {
    /// White card with a hairline border, the base surface of every block on screen.
    func cardStyle(radius: CGFloat = Theme.cardRadius) -> some View {
        background(Theme.card, in: .rect(cornerRadius: radius))
            .overlay {
                RoundedRectangle(cornerRadius: radius)
                    .strokeBorder(Theme.cardBorder, lineWidth: 1)
            }
    }
}
