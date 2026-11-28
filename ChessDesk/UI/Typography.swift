import SwiftUI
import UIKit

// Type scale from `docs/design.md`, section 4. Newsreader for titles and
// editorial prose, Geist for everything else, Geist Mono for PGN and FEN only.
// Sizes are a little larger than the web scale (14 px body reads small on a
// phone) and all of them follow Dynamic Type.

enum CDFont {
    case display        // Newsreader 34, marketing hero
    case pageTitle      // Newsreader 30
    case plateTitle     // Newsreader 24, card and sheet headlines
    case serifCard      // Newsreader 19.5 medium, course and card names
    case lede           // Newsreader 19, editorial prose and move notes
    case ledeSmall      // Newsreader 16.5, secondary notes
    case sectionTitle   // Geist 17 semibold
    case cardTitle      // Geist 15.5 semibold
    case body           // Geist 15.5
    case bodyStrong     // Geist 15.5 medium
    case small          // Geist 14
    case meta           // Geist 12.5
    case metric         // Geist 34 semibold, tabular
    case metricMedium   // Geist 24 semibold, tabular
    case san            // Geist 15.5 medium, tabular
    case button         // Geist 15.5 medium
    case buttonLarge    // Geist 16.5 semibold, the label of a large action
    case mono           // Geist Mono 13.5

    var font: Font {
        let spec = spec
        return Font.custom(spec.name, size: spec.size, relativeTo: spec.style)
    }

    var uiFont: UIFont {
        let spec = spec
        let base = UIFont(name: spec.name, size: spec.size) ?? .systemFont(ofSize: spec.size)
        return UIFontMetrics(forTextStyle: spec.uiStyle).scaledFont(for: base)
    }

    /// Extra line spacing so the leading matches the design scale.
    var lineSpacing: CGFloat {
        switch self {
        case .display, .pageTitle: 2
        case .plateTitle, .serifCard: 3
        case .lede: 6
        case .ledeSmall: 4.5
        case .body, .bodyStrong: 5
        case .small: 4
        case .meta: 2.5
        default: 0
        }
    }

    var tracking: CGFloat {
        switch self {
        case .display: -0.4
        case .pageTitle: -0.3
        case .plateTitle: -0.15
        case .sectionTitle: -0.2
        case .metric: -1
        case .metricMedium: -0.6
        case .buttonLarge: -0.15
        default: 0
        }
    }

    private struct Spec {
        let name: String
        let size: CGFloat
        let style: Font.TextStyle
        let uiStyle: UIFont.TextStyle
    }

    private var spec: Spec {
        switch self {
        case .display: Spec(name: "Newsreader72pt-Medium", size: 34, style: .largeTitle, uiStyle: .largeTitle)
        case .pageTitle: Spec(name: "Newsreader72pt-Medium", size: 30, style: .title, uiStyle: .title1)
        case .plateTitle: Spec(name: "Newsreader72pt-Medium", size: 24, style: .title2, uiStyle: .title2)
        case .serifCard: Spec(name: "Newsreader16pt-Medium", size: 19.5, style: .title3, uiStyle: .title3)
        case .lede: Spec(name: "Newsreader16pt-Regular", size: 19, style: .body, uiStyle: .body)
        case .ledeSmall: Spec(name: "Newsreader16pt-Regular", size: 16.5, style: .callout, uiStyle: .callout)
        case .sectionTitle: Spec(name: "Geist-SemiBold", size: 17, style: .headline, uiStyle: .headline)
        case .cardTitle: Spec(name: "Geist-SemiBold", size: 15.5, style: .subheadline, uiStyle: .subheadline)
        case .body: Spec(name: "Geist-Regular", size: 15.5, style: .body, uiStyle: .body)
        case .bodyStrong: Spec(name: "Geist-Medium", size: 15.5, style: .body, uiStyle: .body)
        case .small: Spec(name: "Geist-Regular", size: 14, style: .subheadline, uiStyle: .subheadline)
        case .meta: Spec(name: "Geist-Regular", size: 12.5, style: .footnote, uiStyle: .footnote)
        case .metric: Spec(name: "Geist-SemiBold", size: 34, style: .largeTitle, uiStyle: .largeTitle)
        case .metricMedium: Spec(name: "Geist-SemiBold", size: 24, style: .title2, uiStyle: .title2)
        case .san: Spec(name: "Geist-Medium", size: 15.5, style: .body, uiStyle: .body)
        case .button: Spec(name: "Geist-Medium", size: 15.5, style: .body, uiStyle: .body)
        case .buttonLarge: Spec(name: "Geist-SemiBold", size: 16.5, style: .body, uiStyle: .body)
        case .mono: Spec(name: "GeistMono-Regular", size: 13.5, style: .footnote, uiStyle: .footnote)
        }
    }
}

extension View {
    /// Applies a ChessDesk text style: font, tracking and leading.
    func cdFont(_ style: CDFont) -> some View {
        font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }

    /// Tabular, lining figures: every number in the UI.
    func cdNumber() -> some View {
        monospacedDigit()
    }
}

enum CDFormat {
    /// "1,738": ratings and counts always carry a thousands separator.
    static func count(_ value: Int) -> String {
        value.formatted(.number.grouping(.automatic).locale(Locale(identifier: "en_US")))
    }

    static func plural(_ value: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count(value)) \(value == 1 ? singular : plural ?? singular + "s")"
    }
}
