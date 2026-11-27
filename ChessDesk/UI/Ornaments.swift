import SwiftUI

// The printer's furniture of a chess book (`docs/design.md`, "Emblems and
// ornaments"), drawn from the site's `components/ui/ornaments.tsx`. Brand
// moments only: the one plate of a screen, the opening of a chapter, the
// thing being sold. Never on a working screen (the trainer, a list). They are
// worth something because they are rare.

// MARK: Corner flourish

/// A brass bracket with a parallel inner rule, a lozenge on each arm's end
/// and a dot at the angle. Drawn for the top left corner on a 26 grid.
struct CornerFlourish: View {
    enum Corner: CaseIterable {
        case topLeading, topTrailing, bottomLeading, bottomTrailing

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }

        var scale: CGSize {
            switch self {
            case .topLeading: CGSize(width: 1, height: 1)
            case .topTrailing: CGSize(width: -1, height: 1)
            case .bottomLeading: CGSize(width: 1, height: -1)
            case .bottomTrailing: CGSize(width: -1, height: -1)
            }
        }
    }

    let corner: Corner
    var size: CGFloat = 20
    var color = CD.accent

    var body: some View {
        let unit = size / 26
        ZStack {
            Bracket().stroke(color, style: StrokeStyle(lineWidth: 1, lineCap: .round))
            InnerRule()
                .stroke(color.opacity(0.6), style: StrokeStyle(lineWidth: 0.75, lineCap: .round, lineJoin: .round))
            Lozenges().stroke(color, style: StrokeStyle(lineWidth: 0.75, lineJoin: .round))
            Circle()
                .fill(color)
                .frame(width: 2.2 * unit, height: 2.2 * unit)
                .position(x: 8.5 * unit, y: 8.5 * unit)
        }
        .frame(width: size, height: size)
        .scaleEffect(corner.scale)
        .accessibilityHidden(true)
    }

    nonisolated private struct Bracket: Shape {
        func path(in rect: CGRect) -> Path {
            let u = rect.width / 26
            var path = Path()
            path.move(to: CGPoint(x: 1.5 * u, y: 17 * u))
            path.addLine(to: CGPoint(x: 1.5 * u, y: 4.5 * u))
            path.addArc(
                center: CGPoint(x: 4.5 * u, y: 4.5 * u),
                radius: 3 * u,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: 17 * u, y: 1.5 * u))
            return path
        }
    }

    nonisolated private struct InnerRule: Shape {
        func path(in rect: CGRect) -> Path {
            let u = rect.width / 26
            var path = Path()
            path.move(to: CGPoint(x: 5.5 * u, y: 11.5 * u))
            path.addLine(to: CGPoint(x: 5.5 * u, y: 5.5 * u))
            path.addLine(to: CGPoint(x: 11.5 * u, y: 5.5 * u))
            return path
        }
    }

    nonisolated private struct Lozenges: Shape {
        func path(in rect: CGRect) -> Path {
            let u = rect.width / 26
            var path = Path()
            for centre in [CGPoint(x: 22.5, y: 1.5), CGPoint(x: 1.5, y: 22.5)] {
                path.move(to: CGPoint(x: (centre.x - 2) * u, y: centre.y * u))
                path.addLine(to: CGPoint(x: centre.x * u, y: (centre.y - 2) * u))
                path.addLine(to: CGPoint(x: (centre.x + 2) * u, y: centre.y * u))
                path.addLine(to: CGPoint(x: centre.x * u, y: (centre.y + 2) * u))
                path.closeSubpath()
            }
            return path
        }
    }
}

/// The four flourishes of a framed plate, 10 pt inside its edge.
struct PlateCorners: View {
    var size: CGFloat = 20

    var body: some View {
        ZStack {
            ForEach(CornerFlourish.Corner.allCases, id: \.self) { corner in
                CornerFlourish(corner: corner, size: size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
            }
        }
        .padding(10)
        .allowsHitTesting(false)
    }
}

// MARK: Plate

/// THE framed element of a view. One per screen height, never two side by side.
enum PlateTone {
    /// The lead panel: surface-1, strong hairline.
    case standard
    /// A commercial surface: brass hairline and a faint brass wash from the top right.
    case premium
}

private struct Plate: ViewModifier {
    let tone: PlateTone
    let padding: CGFloat

    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: CD.Radius.xl, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    // `--cd-shadow-raise`: the depth of the one raised card, not a glow.
                    shape.fill(CD.surface1)
                        .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
                    if tone == .premium {
                        shape.fill(
                            EllipticalGradient(
                                colors: [CD.accent.opacity(0.12), CD.accent.opacity(0)],
                                center: .topTrailing,
                                startRadiusFraction: 0,
                                endRadiusFraction: 0.75
                            )
                        )
                    }
                }
            }
            .overlay(shape.strokeBorder(tone == .premium ? CD.accentLine : CD.lineStrong, lineWidth: 1))
            .overlay(PlateCorners(size: sizeClass == .regular ? 30 : 20))
    }
}

extension View {
    /// Frames the view as the screen's plate: xl radius, hairline, four brass corners.
    func plate(_ tone: PlateTone = .standard, padding: CGFloat = CD.Space.s24) -> some View {
        modifier(Plate(tone: tone, padding: padding))
    }
}

// MARK: Rules and marks

/// Hairline, a brass lozenge between two ink dots, hairline. Separates a
/// title block from what follows, on major openings only.
struct OrnamentRule: View {
    var body: some View {
        HStack(spacing: CD.Space.s8) {
            CDHairline(color: CD.lineStrong)
            Canvas { context, _ in
                for x in [9.0, 35.0] {
                    context.fill(Path(ellipseIn: CGRect(x: x - 1, y: 5, width: 2, height: 2)), with: .color(CD.ink4))
                }
                context.stroke(
                    lozenge(centre: CGPoint(x: 22, y: 6), radius: 4.8),
                    with: .color(CD.accent),
                    style: StrokeStyle(lineWidth: 0.9, lineJoin: .round)
                )
                context.fill(lozenge(centre: CGPoint(x: 22, y: 6), radius: 2), with: .color(CD.accent))
            }
            .frame(width: 44, height: 12)
            CDHairline(color: CD.lineStrong)
        }
        .accessibilityHidden(true)
    }
}

/// "Included": the rule's lozenge on its own. Never a generic check in a
/// comparison. Decorative: the text beside it carries the meaning.
struct IncludedMark: View {
    var size: CGFloat = 16
    var color = CD.accent

    var body: some View {
        Canvas { context, canvasSize in
            let unit = canvasSize.width / 16
            context.scaleBy(x: unit, y: unit)
            context.stroke(
                lozenge(centre: CGPoint(x: 8, y: 8), radius: 6.4),
                with: .color(color),
                style: StrokeStyle(lineWidth: 1, lineJoin: .round)
            )
            context.fill(lozenge(centre: CGPoint(x: 8, y: 8), radius: 2.8), with: .color(color))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private func lozenge(centre: CGPoint, radius: CGFloat) -> Path {
    var path = Path()
    path.move(to: CGPoint(x: centre.x, y: centre.y - radius))
    path.addLine(to: CGPoint(x: centre.x + radius, y: centre.y))
    path.addLine(to: CGPoint(x: centre.x, y: centre.y + radius))
    path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
    path.closeSubpath()
    return path
}

// MARK: Moving edge

/// The light that runs round the lead brass action (`.cd-moving-border--brass`).
/// One per screen. Still when Reduce Motion is on.
struct MovingEdge: View {
    let radius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var turning = false

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(
                AngularGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .clear, location: 0.55),
                        .init(color: CD.glint, location: 0.72),
                        .init(color: CD.accent, location: 0.82),
                        .init(color: .clear, location: 0.92),
                        .init(color: .clear, location: 1),
                    ],
                    center: .center,
                    angle: .degrees(turning ? 360 : 0)
                ),
                lineWidth: 1.5
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { turning = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
