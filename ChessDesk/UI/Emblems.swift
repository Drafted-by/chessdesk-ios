import SwiftUI

// Engraved emblems (`docs/design.md`, section 10), drawn from the site's
// `components/ui/emblems.tsx` on the same 32 grid: a 3 × 3 board fragment
// with its dark squares hatched, a subject in paper ink that breaks out of
// the frame, and exactly one brass element. One emblem names one feature;
// it never replaces a control icon and never sits on a coloured tile.

struct Emblem: View {
    enum Kind {
        /// A gauge, the needle in brass: ratings, Reach 1000 Elo.
        case rating
        /// A seal with a crown, the seal in brass: Premium.
        case premium
    }

    let kind: Kind
    var size: CGFloat = 40
    /// The knock-out colour: must equal the surface the emblem sits on.
    var surface = CD.surface1

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 32, y: canvasSize.height / 32)
            let compact = size <= 28
            plate(&context, compact: compact)
            switch kind {
            case .rating: rating(&context, compact: compact)
            case .premium: premium(&context, compact: compact)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var ink: GraphicsContext.Shading { .color(CD.ink) }
    private var muted: GraphicsContext.Shading { .color(CD.ink4) }
    private var accent: GraphicsContext.Shading { .color(CD.accent) }
    private var ground: GraphicsContext.Shading { .color(surface) }

    /// Compact strokes are a quarter heavier so they hold at 20 to 28 pt.
    private func weight(_ compact: Bool, _ value: CGFloat) -> CGFloat {
        compact ? value * 1.25 : value
    }

    private func round(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }

    // MARK: Board fragment

    private func plate(_ context: inout GraphicsContext, compact: Bool) {
        let origin: CGFloat = 3.5
        let square: CGFloat = 7.5
        var hatches = Path()
        for column in 0..<3 {
            for row in 0..<3 where (column + row) % 2 == 1 {
                let rect = CGRect(x: origin + CGFloat(column) * square, y: origin + CGFloat(row) * square, width: square, height: square)
                hatches.addPath(Self.hatch(rect: rect, circle: nil, pitch: compact ? 2.5 : 1.6))
            }
        }
        var layer = context
        layer.opacity = compact ? 0.7 : 0.75
        layer.stroke(hatches, with: muted, lineWidth: compact ? 0.8 : 0.6)
        if !compact {
            var grid = Path()
            for index in 1..<3 {
                let offset = origin + CGFloat(index) * square
                grid.move(to: CGPoint(x: offset, y: origin))
                grid.addLine(to: CGPoint(x: offset, y: origin + 3 * square))
                grid.move(to: CGPoint(x: origin, y: offset))
                grid.addLine(to: CGPoint(x: origin + 3 * square, y: offset))
            }
            var gridLayer = context
            gridLayer.opacity = 0.6
            gridLayer.stroke(grid, with: muted, lineWidth: 0.5)
        }
        context.stroke(
            Path(CGRect(x: origin, y: origin, width: 3 * square, height: 3 * square)),
            with: muted,
            lineWidth: compact ? 0.9 : 0.75
        )
    }

    /// 45° engraving hatch ("/" strokes, x + y = c) clipped to a rectangle
    /// and optionally to a circle.
    static func hatch(rect: CGRect, circle: (centre: CGPoint, radius: CGFloat)?, pitch: CGFloat) -> Path {
        var low = rect.minX + rect.minY
        var high = rect.maxX + rect.maxY
        if let circle {
            low = max(low, circle.centre.x + circle.centre.y - circle.radius * 2.squareRoot())
            high = min(high, circle.centre.x + circle.centre.y + circle.radius * 2.squareRoot())
        }
        var path = Path()
        var c = ((low + 0.01) / pitch).rounded(.up) * pitch
        while c < high - 0.01 {
            defer { c += pitch }
            var start = max(rect.minX, c - rect.maxY)
            var end = min(rect.maxX, c - rect.minY)
            if let circle {
                let k = c - circle.centre.y
                let b = -2 * (circle.centre.x + k)
                let constant = circle.centre.x * circle.centre.x + k * k - circle.radius * circle.radius
                let discriminant = b * b - 8 * constant
                if discriminant <= 0 { continue }
                let root = discriminant.squareRoot()
                start = max(start, (-b - root) / 4)
                end = min(end, (-b + root) / 4)
            }
            if end - start < 0.35 { continue }
            path.move(to: CGPoint(x: start, y: c - start))
            path.addLine(to: CGPoint(x: end, y: c - end))
        }
        return path
    }

    private static func polygon(_ numbers: [CGFloat]) -> Path {
        var path = Path()
        for index in stride(from: 0, to: numbers.count - 1, by: 2) {
            let point = CGPoint(x: numbers[index], y: numbers[index + 1])
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private static func line(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y1))
        path.addLine(to: CGPoint(x: x2, y: y2))
        return path
    }

    private static func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }

    /// The upper half of a circle, from its left end to its right end.
    private static func dome(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: x, y: y), radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
        return path
    }

    // MARK: Rating

    private func rating(_ context: inout GraphicsContext, compact: Bool) {
        // The dial, cut out of the board.
        var dial = Self.dome(16, 24.6, 13.4)
        dial.closeSubpath()
        context.fill(dial, with: ground)
        context.stroke(dial, with: ground, style: round(2.4))
        if !compact {
            var layer = context
            layer.opacity = 0.5
            layer.stroke(
                Self.hatch(rect: CGRect(x: 16, y: 10, width: 14, height: 14.6), circle: (CGPoint(x: 16, y: 24), 12.2), pitch: 1.8),
                with: muted,
                lineWidth: 0.5
            )
        }
        context.stroke(Self.dome(16, 24, 12.6), with: ink, style: round(weight(compact, 1.2)))
        var ticks = Path()
        let count = compact ? 4 : 8
        for index in 0...count {
            let angle = Double.pi * (1 - Double(index) / Double(count))
            let inner: CGFloat = compact || index % 2 == 0 ? 8.6 : 9.4
            ticks.move(to: CGPoint(x: 16 + inner * cos(angle), y: 24 - inner * sin(angle)))
            ticks.addLine(to: CGPoint(x: 16 + 10.6 * cos(angle), y: 24 - 10.6 * sin(angle)))
        }
        context.stroke(ticks, with: ink, style: round(weight(compact, 0.75)))
        context.stroke(Self.line(1.8, 24.6, 30.2, 24.6), with: ink, style: round(weight(compact, 1.2)))
        if !compact {
            var layer = context
            layer.opacity = 0.5
            layer.stroke(Self.line(4.6, 27.6, 27.4, 27.6), with: ink, style: round(0.6))
        }
        // The needle.
        let needle = Self.line(16, 24, 22.6, 13.6)
        context.stroke(needle, with: ground, style: round(3.4))
        context.stroke(needle, with: accent, style: round(weight(compact, 1.5)))
        context.fill(Self.disc(16, 24, 2.8), with: ground)
        context.fill(Self.disc(16, 24, 2.3), with: accent)
    }

    // MARK: Premium

    private func premium(_ context: inout GraphicsContext, compact: Bool) {
        var ribbons = Self.polygon([11.2, 19.6, 8.4, 29.4, 11.4, 27.8, 13.4, 30.2, 15.6, 21.4])
        ribbons.addPath(Self.polygon([20.8, 19.6, 23.6, 29.4, 20.6, 27.8, 18.6, 30.2, 16.4, 21.4]))
        context.fill(ribbons, with: ground)
        context.stroke(ribbons, with: ground, style: round(2.4))
        context.fill(ribbons, with: ink)
        context.stroke(ribbons, with: ink, style: round(0.4))
        if !compact {
            var shade = Self.line(22.4, 24.6, 20.8, 24)
            shade.addPath(Self.line(22.9, 26.6, 21.3, 26))
            var layer = context
            layer.opacity = 0.75
            layer.stroke(shade, with: ground, style: round(0.6))
        }
        // The seal.
        context.fill(Self.disc(16, 14, 10.2), with: ground)
        context.fill(Self.disc(16, 14, 9), with: accent)
        if !compact {
            var layer = context
            layer.opacity = 0.65
            layer.stroke(Self.disc(16, 14, 7.6), with: ground, lineWidth: 0.5)
        }
        let crown = Self.polygon([10.8, 17.6, 10, 10.8, 13.4, 13.6, 16, 9.2, 18.6, 13.6, 22, 10.8, 21.2, 17.6])
        context.fill(crown, with: ground)
        context.stroke(crown, with: ground, style: round(0.6))
        context.stroke(Self.line(11, 19.2, 21, 19.2), with: ground, style: round(weight(compact, 1)))
    }
}
