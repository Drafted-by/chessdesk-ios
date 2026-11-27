import SwiftUI

// The ChessDesk design tokens, mirrored from the site (`apps/web/app/globals.css`,
// spec in `apps/web/docs/design.md`). One brass accent, warm graphite, paper ink.
// Never hardcode a colour in a view: add the token here first.

nonisolated extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

nonisolated enum CD {
    // MARK: Surfaces

    static let canvas = Color(hex: 0x100F0D)
    static let surface1 = Color(hex: 0x171513)
    static let surface2 = Color(hex: 0x1F1C19)
    static let surface3 = Color(hex: 0x282521)
    static let surface4 = Color(hex: 0x33302B)

    static let line = Color(hex: 0xEFEAE2, opacity: 0.08)
    static let lineStrong = Color(hex: 0xEFEAE2, opacity: 0.14)
    static let lineHover = Color(hex: 0xEFEAE2, opacity: 0.24)

    // MARK: Ink

    static let ink = Color(hex: 0xEFEAE2)
    static let ink2 = Color(hex: 0xBDB6AE)
    static let ink3 = Color(hex: 0x9D978F)
    /// Meta only, on canvas or surface-1.
    static let ink4 = Color(hex: 0x857F78)

    // MARK: Brass (the one accent)

    static let accent = Color(hex: 0xE0B676)
    static let accentStrong = Color(hex: 0xEDCC95)
    static let accentInk = Color(hex: 0x23190A)
    static let accentSoft = Color(hex: 0xE0B676, opacity: 0.12)
    static let accentLine = Color(hex: 0xE0B676, opacity: 0.38)

    // MARK: Outcomes

    static let win = Color(hex: 0x75C59B)
    static let draw = Color(hex: 0xA39D96)
    static let loss = Color(hex: 0xE47D70)
    static let caution = Color(hex: 0xE7C952)
    static let danger = Color(hex: 0xE85854)

    static let sideWhite = Color(hex: 0xEFEAE2)
    static let sideBlack = Color(hex: 0x0B0A09)

    // MARK: Board

    nonisolated enum Board {
        static let light = Color(hex: 0xF0D9B5)
        static let dark = Color(hex: 0xB58863)
        static let lastMove = Color(.sRGB, red: 205 / 255, green: 150 / 255, blue: 20 / 255, opacity: 0.5)
        static let selected = Color(.sRGB, red: 190 / 255, green: 120 / 255, blue: 0, opacity: 0.62)
        static let destination = Color(hex: 0x100F0D, opacity: 0.32)
        static let check = Color(hex: 0xE85854, opacity: 0.85)
        static let wrong = Color(hex: 0xE85854, opacity: 0.62)
        static let right = Color(hex: 0x79C77C, opacity: 0.6)
        static let sealRight = Color(hex: 0x79C77C)
        static let sealWrong = Color(hex: 0xE85854)
    }

    /// Arrow brushes: the site's four meanings, same colours.
    nonisolated enum Arrow {
        static let move = Color(hex: 0x0F6E1C)
        static let reply = Color(hex: 0x882020)
        static let alternative = Color(hex: 0x003088)
        static let idea = Color(hex: 0xA86400)
        static let layerOpacity = 0.6
    }

    // MARK: Shape

    nonisolated enum Radius {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
    }

    /// Spacing scale: 2, 4, 6, 8, 12, 16, 20, 24, 32, 40, 56, 80.
    nonisolated enum Space {
        static let s2: CGFloat = 2
        static let s4: CGFloat = 4
        static let s6: CGFloat = 6
        static let s8: CGFloat = 8
        static let s12: CGFloat = 12
        static let s16: CGFloat = 16
        static let s20: CGFloat = 20
        static let s24: CGFloat = 24
        static let s32: CGFloat = 32
        static let s40: CGFloat = 40
        static let s56: CGFloat = 56
    }

    /// Reading width for prose and the widest a phone-style column gets on iPad.
    static let readingWidth: CGFloat = 640
    static let pageMaxWidth: CGFloat = 1180

    // MARK: Motion

    nonisolated enum Motion {
        /// `--cd-ease`: cubic-bezier(0.2, 0, 0, 1).
        static func ease(_ duration: Double) -> Animation {
            .timingCurve(0.2, 0, 0, 1, duration: duration)
        }

        static let press = ease(0.12)
        static let state = ease(0.18)
        static let enter = ease(0.26)
        static let pieceMove = ease(0.2)
    }
}

extension View {
    /// A 1 px hairline border on a rounded shape.
    func hairline(_ color: Color = CD.line, radius: CGFloat = CD.Radius.lg) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(color, lineWidth: 1))
    }

    /// Page gutter: 16 pt on phones, 32 pt in a regular-width layout.
    func pageGutter() -> some View {
        modifier(PageGutter())
    }
}

private struct PageGutter: ViewModifier {
    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        content.padding(.horizontal, sizeClass == .regular ? CD.Space.s32 : CD.Space.s16)
    }
}
