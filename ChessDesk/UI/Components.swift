import ChessCore
import SwiftUI

// The kit: the native counterparts of the site's `components/ui`. Screens
// compose these; a screen that needs something else adds it here.

// MARK: Buttons

/// `primary` is brass and there is one per view. `lead` is the same action
/// on the screen's plate, with the moving edge. `secondary` is the neutral
/// action, `ghost` the quiet one.
struct CDButtonStyle: ButtonStyle {
    enum Variant { case primary, lead, secondary, ghost }
    enum Size { case small, medium, large }

    var variant: Variant = .secondary
    var size: Size = .medium
    var fullWidth = false

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let height: CGFloat = switch size {
        case .small: 34
        case .medium: 44
        case .large: 52
        }
        return configuration.label
            .cdFont(.button)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, variant == .ghost ? 10 : size == .small ? 12 : 18)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: height)
            .background(background(pressed: configuration.isPressed), in: shape)
            .overlay(shape.strokeBorder(border, lineWidth: 1))
            .overlay { if variant == .lead { MovingEdge(radius: radius) } }
            .shadow(color: variant == .lead ? CD.accent.opacity(0.22) : .clear, radius: 10, y: 6)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(CD.Motion.press, value: configuration.isPressed)
            .contentShape(shape)
    }

    private var radius: CGFloat { size == .large ? 10 : CD.Radius.md }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var foreground: Color {
        switch variant {
        case .primary, .lead: CD.accentInk
        case .secondary: CD.ink
        case .ghost: CD.ink2
        }
    }

    private func background(pressed: Bool) -> AnyShapeStyle {
        switch variant {
        case .primary: AnyShapeStyle(pressed ? CD.accentStrong : CD.accent)
        case .lead:
            pressed
                ? AnyShapeStyle(CD.accentStrong)
                : AnyShapeStyle(LinearGradient(colors: [CD.accent, CD.accentStrong], startPoint: .top, endPoint: .bottom))
        case .secondary: AnyShapeStyle(pressed ? CD.surface3 : CD.surface2)
        case .ghost: AnyShapeStyle(pressed ? CD.surface2 : Color.clear)
        }
    }

    private var border: Color {
        switch variant {
        case .primary, .ghost: .clear
        case .lead: CD.accentLine
        case .secondary: CD.lineStrong
        }
    }
}

extension ButtonStyle where Self == CDButtonStyle {
    static func cd(
        _ variant: CDButtonStyle.Variant = .secondary,
        size: CDButtonStyle.Size = .medium,
        fullWidth: Bool = false
    ) -> CDButtonStyle {
        CDButtonStyle(variant: variant, size: size, fullWidth: fullWidth)
    }
}

/// A whole-row or whole-card tap target: dims slightly while pressed.
struct CDPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(CD.Motion.press, value: configuration.isPressed)
    }
}

// MARK: Surfaces

struct CDCard<Content: View>: View {
    enum Tone { case standard, raised, inset }

    var tone: Tone = .standard
    var padding: CGFloat = CD.Space.s16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
            .hairline(tone == .raised ? CD.lineStrong : CD.line)
    }

    private var fill: Color {
        switch tone {
        case .standard: CD.surface1
        case .raised: CD.surface2
        case .inset: CD.canvas
        }
    }
}

struct CDHairline: View {
    var color = CD.line

    var body: some View {
        Rectangle().fill(color).frame(height: 1)
    }
}

// MARK: Small marks

/// The side a player has: a 9 pt round disc in the piece colour. Never a square.
struct SideSwatch: View {
    let side: Side
    var size: CGFloat = 9

    var body: some View {
        Circle()
            .fill(side == .white ? CD.sideWhite : CD.sideBlack)
            .overlay(Circle().strokeBorder(side == .white ? Color.clear : CD.ink4, lineWidth: 1))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

struct CDBadge: View {
    enum Tone { case neutral, accent, premium, win }

    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.custom("Geist-Medium", size: 11.5, relativeTo: .caption))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
    }

    private var foreground: Color {
        switch tone {
        case .neutral: CD.ink2
        case .accent: CD.accentStrong
        case .premium: CD.accentInk
        case .win: CD.win
        }
    }

    private var background: Color {
        switch tone {
        case .neutral, .win: .clear
        case .accent: CD.accentSoft
        case .premium: CD.accent
        }
    }

    private var border: Color {
        switch tone {
        case .neutral: CD.lineStrong
        case .accent: CD.accentLine
        case .premium: .clear
        case .win: CD.win.opacity(0.4)
        }
    }
}

/// A thin progress meter. The only fully rounded shape in the kit.
struct CDMeter: View {
    let value: Double
    var tint = CD.accent
    var height: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CD.surface4)
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: Brand

/// The 2×2 mark: two brass squares on the long diagonal, two outlined.
struct LogoMark: View {
    var size: CGFloat = 22

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 24
            func square(_ x: CGFloat, _ y: CGFloat) -> Path {
                Path(
                    roundedRect: CGRect(x: x * unit, y: y * unit, width: 9.5 * unit, height: 9.5 * unit),
                    cornerRadius: 2 * unit
                )
            }
            context.fill(square(2, 2), with: .color(CD.accent))
            context.fill(square(12.5, 12.5), with: .color(CD.accent))
            let outline = StrokeStyle(lineWidth: 1.5 * unit)
            context.stroke(square(12.5, 2), with: .color(CD.ink4), style: outline)
            context.stroke(square(2, 12.5), with: .color(CD.ink4), style: outline)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct Wordmark: View {
    var size: CGFloat = 22

    var body: some View {
        HStack(spacing: size * 0.4) {
            LogoMark(size: size)
            Text("chessdesk")
                .font(.custom("Newsreader72pt-Medium", fixedSize: size * 0.98))
                .tracking(-0.2)
                .foregroundStyle(CD.ink)
                .offset(y: -1)
        }
        .accessibilityElement()
        .accessibilityLabel("ChessDesk")
    }
}

// MARK: Headers and states

struct SectionHeader: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s4) {
            Text(title)
                .cdFont(.sectionTitle)
                .foregroundStyle(CD.ink)
            if let detail {
                Text(detail)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// What a screen shows when its data could not be loaded. Says what happened
/// and offers the one useful action.
struct LoadFailureView: View {
    let title: String
    let message: String
    var retry: (() -> Void)?

    var body: some View {
        VStack(spacing: CD.Space.s16) {
            StaticBoardView(fen: "8/8/8/3k4/8/3K4/8/8 w - - 0 1", orientation: .white)
                .frame(width: 112, height: 112)
                .opacity(0.9)
            VStack(spacing: CD.Space.s6) {
                Text(title)
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text(message)
                    .cdFont(.body)
                    .foregroundStyle(CD.ink2)
                    .multilineTextAlignment(.center)
            }
            if let retry {
                Button("Try again", action: retry)
                    .buttonStyle(.cd(.secondary))
            }
        }
        .padding(CD.Space.s32)
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LoadingView: View {
    var body: some View {
        ProgressView()
            .tint(CD.ink3)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: Segmented

/// Two to five exclusive views of the same data.
struct CDSegmented<Value: Hashable>: View {
    let options: [(value: Value, label: String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let isSelected = option.value == selection
                Button {
                    withAnimation(CD.Motion.state) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(.custom("Geist-Medium", size: 14, relativeTo: .subheadline))
                        .foregroundStyle(isSelected ? CD.ink : CD.ink3)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background(
                            isSelected ? CD.surface3 : .clear,
                            in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
        .hairline(CD.line, radius: CD.Radius.md)
    }
}
