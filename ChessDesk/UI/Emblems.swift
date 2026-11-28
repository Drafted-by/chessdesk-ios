import SwiftUI

// Engraved emblems (`docs/design.md`, section 10), carried over from the
// site's `components/ui/emblems.tsx` on the same 32 grid: a 3 × 3 board
// fragment with its dark squares hatched, a subject in paper ink that breaks
// out of the frame, lit from the top left, and exactly one brass element.
//
// One emblem names one feature, wherever the feature is offered, named or
// entered (a hub row, a page head, an empty state). It never replaces a
// control icon and never sits on a coloured tile. Two cuts: full at 32 pt and
// up, compact at 28 pt and under (lighter plate, no fine detail).
//
// The path data below is the site's, unchanged: to add an emblem, copy its
// drawing from `emblems.tsx` and keep the two files alike.

struct Emblem: View {
    enum Kind: String, CaseIterable, Sendable {
        /// A reading lens, the rim in brass: game review.
        case review
        /// A crossed move and the better one in brass: your mistakes.
        case mistakes
        /// An open book and its tree, the main line in brass: repertoires.
        case repertoire
        /// A bound book, the ribbon in brass: opening courses.
        case course
        /// A knight and its brass target square: puzzles.
        case puzzles
        /// A chess clock, the running side in brass: play a bot.
        case play
        /// A woodpecker on the board, the beak in brass: the Woodpecker Method.
        case woodpecker
        /// Two rulers and a brass sight: the coordinate trainer.
        case coordinates
        /// An evaluation bar and the engine's move in brass: the analysis board.
        case analysis
        /// A compass, the north needle in brass: the opening explorer.
        case explorer
        /// A pawn and its brass arrow: the best move in a position.
        case nextMove
        /// Axes and a brass rating line: progress.
        case insights
        /// A gauge, the needle in brass: ratings, Reach 1000 Elo, the Elo calculator.
        case rating
        /// A palette, one well in brass: the look of the board.
        case theme
        /// A calendar leaf, the day ringed in brass: Daily 5.
        case schedule
        /// A tray and a brass arrow: game import, linked accounts.
        case `import`
        /// A score sheet and a brass pencil: games.
        case games
        /// A seal with a crown, the seal in brass: Premium.
        case premium
        /// A pair of dividers, the hinge in brass: the tools.
        case tools
        /// Three sliders, one knob in brass: settings, a custom opponent.
        case settings
        /// A cameo king, the frame in brass: the account.
        case profile
    }

    let kind: Kind
    var size: CGFloat = 40
    /// The knock-out colour: must equal the surface the emblem sits on.
    var surface = CD.surface1

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 32, y: canvasSize.height / 32)
            kind.draw(EmblemPen(context: context, compact: size <= 28, surface: surface))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: The pen

/// The few gestures every emblem is made of, named after the site's:
/// `plate`, `hatch`, `w`, `Shade`, and the knock-out ("cut") that separates a
/// subject from the board behind it.
nonisolated struct EmblemPen {
    enum Tone { case ink, muted, accent, ground }

    let context: GraphicsContext
    /// `c` in the site's drawings.
    let compact: Bool
    let surface: Color

    private func shading(_ tone: Tone) -> GraphicsContext.Shading {
        switch tone {
        case .ink: .color(CD.ink)
        case .muted: .color(CD.ink4)
        case .accent: .color(CD.accent)
        case .ground: .color(surface)
        }
    }

    private func layer(_ opacity: Double) -> GraphicsContext {
        guard opacity < 1 else { return context }
        var layer = context
        layer.opacity = opacity
        return layer
    }

    /// Compact strokes are a quarter heavier so they hold at 20 to 28 pt.
    func w(_ value: CGFloat) -> CGFloat {
        compact ? (value * 125).rounded() / 100 : value
    }

    /// The same pen, moved: a `<g transform="translate(x y)">`.
    func moved(_ x: CGFloat, _ y: CGFloat) -> EmblemPen {
        var moved = context
        moved.translateBy(x: x, y: y)
        return EmblemPen(context: moved, compact: compact, surface: surface)
    }

    func fill(_ path: Path, _ tone: Tone, opacity: Double = 1) {
        layer(opacity).fill(path, with: shading(tone))
    }

    func fill(_ data: String, _ tone: Tone, opacity: Double = 1) {
        fill(Path(svg: data), tone, opacity: opacity)
    }

    func stroke(
        _ path: Path, _ tone: Tone, _ width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter,
        dash: [CGFloat] = [], opacity: Double = 1
    ) {
        layer(opacity).stroke(
            path,
            with: shading(tone),
            style: StrokeStyle(lineWidth: width, lineCap: cap, lineJoin: join, miterLimit: 4, dash: dash)
        )
    }

    func stroke(
        _ data: String, _ tone: Tone, _ width: CGFloat, cap: CGLineCap = .butt, join: CGLineJoin = .miter,
        dash: [CGFloat] = [], opacity: Double = 1
    ) {
        stroke(Path(svg: data), tone, width, cap: cap, join: join, dash: dash, opacity: opacity)
    }

    /// A shape filled and outlined in one tone, joins rounded: the subject
    /// itself, or (in `ground`) the gap it cuts out of the board.
    func solid(_ path: Path, _ tone: Tone, _ width: CGFloat) {
        fill(path, tone)
        stroke(path, tone, width, join: .round)
    }

    func solid(_ data: String, _ tone: Tone, _ width: CGFloat) {
        solid(Path(svg: data), tone, width)
    }

    /// Engraved shading on the lower right of a form, in the surface colour
    /// over ink. The full cut only.
    func shade(_ data: String, _ width: CGFloat = 0.6) {
        guard !compact else { return }
        stroke(data, .ground, width, cap: .round, opacity: 0.75)
    }

    func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }

    func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - rx, y: y - ry, width: 2 * rx, height: 2 * ry))
    }

    func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat, _ radius: CGFloat = 0) -> Path {
        let rect = CGRect(x: x, y: y, width: width, height: height)
        return radius > 0 ? Path(roundedRect: rect, cornerRadius: radius, style: .circular) : Path(rect)
    }

    /// 45° engraving hatch ("/" strokes, x + y = c) clipped to a rectangle
    /// and optionally to a circle.
    func hatch(
        _ rect: CGRect = CGRect(x: -1000, y: -1000, width: 2000, height: 2000),
        circle: (x: CGFloat, y: CGFloat, radius: CGFloat)? = nil, pitch: CGFloat
    ) -> Path {
        var low = rect.minX + rect.minY
        var high = rect.maxX + rect.maxY
        if let circle {
            low = max(low, circle.x + circle.y - circle.radius * 2.squareRoot())
            high = min(high, circle.x + circle.y + circle.radius * 2.squareRoot())
        }
        var path = Path()
        var c = ((low + 0.01) / pitch).rounded(.up) * pitch
        while c < high - 0.01 {
            defer { c += pitch }
            var start = max(rect.minX, c - rect.maxY)
            var end = min(rect.maxX, c - rect.minY)
            if let circle {
                let k = c - circle.y
                let b = -2 * (circle.x + k)
                let constant = circle.x * circle.x + k * k - circle.radius * circle.radius
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

    /// The shared ground: a 3 × 3 board fragment (3.5 to 26, 7.5 a square),
    /// dark squares hatched. `skip` leaves a dark square open (column, row).
    func plate(skip: [(Int, Int)] = []) {
        let origin: CGFloat = 3.5
        let square: CGFloat = 7.5
        var hatches = Path()
        for column in 0..<3 {
            for row in 0..<3 where (column + row) % 2 == 1 {
                if skip.contains(where: { $0.0 == column && $0.1 == row }) { continue }
                let cell = CGRect(x: origin + CGFloat(column) * square, y: origin + CGFloat(row) * square, width: square, height: square)
                hatches.addPath(hatch(cell, pitch: compact ? 2.5 : 1.6))
            }
        }
        stroke(hatches, .muted, compact ? 0.8 : 0.6, opacity: compact ? 0.7 : 0.75)
        if !compact {
            stroke("M11 3.5v22.5M18.5 3.5v22.5M3.5 11h22.5M3.5 18.5h22.5", .muted, 0.5, opacity: 0.6)
        }
        stroke(rect(origin, origin, 3 * square, 3 * square), .muted, compact ? 0.9 : 0.75)
    }
}

// MARK: The drawings

private nonisolated extension Emblem.Kind {
    func draw(_ p: EmblemPen) {
        switch self {
        case .review: review(p)
        case .mistakes: mistakes(p)
        case .repertoire: repertoire(p)
        case .course: course(p)
        case .puzzles: puzzles(p)
        case .play: play(p)
        case .woodpecker: woodpecker(p)
        case .coordinates: coordinates(p)
        case .analysis: analysis(p)
        case .explorer: explorer(p)
        case .nextMove: nextMove(p)
        case .insights: insights(p)
        case .rating: rating(p)
        case .theme: theme(p)
        case .schedule: schedule(p)
        case .import: importTray(p)
        case .games: games(p)
        case .premium: premium(p)
        case .tools: tools(p)
        case .settings: settings(p)
        case .profile: profile(p)
        }
    }

    func review(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // The lens knocks out the board and shows it magnified.
        p.fill(p.disc(14, 14, 7.6), .ground)
        p.stroke("M14.75 6.4V21.6M6.4 14.75H21.6", .muted, 0.6, opacity: c ? 0.55 : 0.75)
        let lens = (x: CGFloat(14), y: CGFloat(14), radius: CGFloat(7.6))
        p.stroke(p.hatch(CGRect(x: 14.75, y: 5, width: 8, height: 9.75), circle: lens, pitch: c ? 2.9 : 2.3), .muted, p.w(0.7), opacity: 0.9)
        p.stroke(p.hatch(CGRect(x: 5, y: 14.75, width: 9.75, height: 8), circle: lens, pitch: c ? 2.9 : 2.3), .muted, p.w(0.7), opacity: 0.9)
        if !c { p.stroke("M9.1 11.7a5.7 5.7 0 0 1 3.5-3.4", .ink, 0.9, cap: .round, opacity: 0.8) }
        // Handle: collar in brass, grip in ink with a lit edge.
        p.stroke("M28.3 28.3 22.4 22.4", .ground, 5.4, cap: .round)
        p.stroke("M28.3 28.3 22.4 22.4", .ink, 3.4, cap: .round)
        p.shade("M27.6 27 22.8 22.2", 0.7)
        p.stroke(p.disc(14, 14, 7.6), .accent, p.w(1.7))
        if !c { p.stroke(p.disc(14, 14, 6.05), .accent, 0.5, opacity: 0.55) }
        p.stroke("M19.5 19.5 22.5 22.5", .accent, 2.8)
    }

    func mistakes(_ p: EmblemPen) {
        let c = p.compact
        p.plate(skip: [(2, 0)])
        if !c { p.stroke(p.rect(19.75, 4.75, 5, 5), .accent, 0.75, opacity: 0.9) }
        // The move played: dashed ink, ends in a cross.
        p.stroke("M7.25 19.6V11.2", .ink, p.w(1.3), cap: .round, dash: c ? [2, 1.8] : [1.7, 1.5], opacity: 0.75)
        p.stroke("M5.3 5.3 9.2 9.2M9.2 5.3 5.3 9.2", .ground, 3, cap: .round)
        p.stroke("M5.3 5.3 9.2 9.2M9.2 5.3 5.3 9.2", .ink, p.w(1.5), cap: .round)
        // The better move: brass, with a solid head.
        p.stroke("M9.2 20.3 19.3 10.2", .ground, 3.6, cap: .round)
        p.stroke("M9.2 20.3 19.3 10.2", .accent, p.w(1.9), cap: .round)
        p.solid("M22.3 7.2 21.4 13 16.5 8.1Z", .accent, 0.6)
        // The piece on its origin square, breaking the frame.
        p.fill(p.disc(7.25, 22.25, 4), .ground)
        p.fill(p.disc(7.25, 22.25, 3), .ink)
        p.shade("M9.6 20.6a3 3 0 0 1-4 4", 0.7)
    }

    func repertoire(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let block = "M2.5 28.4c4.5-1.6 9.6-1.4 13.5.8 3.9-2.2 9-2.4 13.5-.8"
        p.stroke(block, .ground, 2.4, cap: .round)
        p.stroke(block, .ink, p.w(0.8), cap: .round, opacity: 0.7)
        // Pages, cut out of the board.
        p.solid("M16 27.4c-3.9-2.2-9-2.4-13.5-.8v-7.4c4.5-1.6 9.6-1.4 13.5.8 3.9-2.2 9-2.4 13.5-.8v7.4c-4.5-1.6-9.6-1.4-13.5.8Z", .ground, 2.4)
        p.stroke("M16 27.4c-3.9-2.2-9-2.4-13.5-.8v-7.4c4.5-1.6 9.6-1.4 13.5.8Z", .ink, p.w(1.1), join: .round)
        p.stroke("M16 27.4c3.9-2.2 9-2.4 13.5-.8v-7.4c-4.5-1.6-9.6-1.4-13.5.8Z", .ink, p.w(1.1), join: .round)
        if !c {
            p.stroke(
                "M4.8 22c3.1-.8 6.2-.6 8.9.4M4.8 24.3c3.1-.8 6.2-.6 8.9.4M18.3 22.4c2.7-1 5.8-1.2 8.9-.4M18.3 24.7c2.7-1 5.8-1.2 8.9-.4",
                .muted, 0.65, cap: .round
            )
        }
        // Side lines in ink.
        let side = "M16 13.4C16 10.4 12.8 9.4 9.6 7.6M16 13.4V5.4"
        p.stroke(side, .ground, 3, cap: .round)
        p.stroke(side, .ink, p.w(1.1), cap: .round, opacity: 0.9)
        p.fill(p.disc(9.1, 7.3, 1.6), .ground)
        p.stroke(p.disc(9.1, 7.3, 1.6), .ink, 1)
        p.fill(p.disc(16, 4.7, 1.6), .ground)
        p.stroke(p.disc(16, 4.7, 1.6), .ink, 1)
        // The main line in brass, from the spine.
        let main = "M16 19.4v-6C16 10.4 19.2 9.4 22.4 7.6"
        p.stroke(main, .ground, 3.4, cap: .round)
        p.stroke(main, .accent, p.w(1.6), cap: .round)
        p.fill(p.disc(22.9, 7.3, 2.1), .accent)
        p.fill(p.disc(16, 13.4, 1.6), .ground)
        p.stroke(p.disc(16, 13.4, 1.6), .accent, 1.1)
    }

    func course(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        p.solid("M8 5.4C8 4.6 8.6 4 9.4 4H24.6C25.4 4 26 4.6 26 5.4V28.2H10.2C9 28.2 8 27.2 8 26Z", .ground, 2.6)
        // The page block under the cover.
        p.stroke("M9.6 26.4v.2c0 .6.5 1.1 1.1 1.1H25.6V6.2", .ink, p.w(0.85), join: .round, opacity: 0.75)
        if !c { p.stroke("M11.2 26.7H24.6M24.6 7.4V25.6", .muted, 0.5, opacity: 0.9) }
        p.fill(p.rect(8, 4, 16.4, 22.2, 1.3), .ink)
        p.stroke("M11 4.6V25.6", .ground, p.w(0.7), opacity: 0.8)
        p.fill(p.rect(13.4, 8, 8.4, 5.4, 0.6), .ground)
        if !c {
            p.stroke("M15 10h5.2M15.8 11.6h3.6", .muted, 0.6, cap: .round)
            p.fill(p.disc(9.6, 5.4, 0.5), .ground, opacity: 0.8)
        }
        p.shade("M22.6 16.4v8.2M20.8 19.6v5M19 22.4v2.2")
        // The ribbon, hanging below the pages.
        let ribbon = "M17.2 24.8H20.4V31.2L18.8 29.6 17.2 31.2Z"
        p.solid(ribbon, .ground, 1.8)
        p.solid(ribbon, .accent, 0.4)
    }

    func puzzles(_ p: EmblemPen) {
        let c = p.compact
        let knight = "M5 26.9c.1-2 1.4-3.3 2.6-4.6-1.2.4-2.6.7-3.6.2-1-.5-1.3-1.5-.8-2.4l3.2-4.6.9-2.3 1 1.3c3 .2 5.4 2.7 5.7 6.4.2 2.2-.4 4.2-1 6Z"
        p.plate(skip: [(1, 0)])
        // Target square, a knight's jump away.
        p.fill(p.rect(11, 3.5, 7.5, 7.5), .accent, opacity: 0.16)
        p.stroke(
            "M11.9 6.2V4.4h1.8M15.8 4.4h1.8v1.8M17.6 8.3v1.8h-1.8M13.7 10.1h-1.8V8.3",
            .accent, p.w(0.9), cap: .round, join: .round
        )
        // The knight, Staunton profile facing left, cut out of the board.
        let g = p.moved(13.5, -0.6)
        g.stroke("M2.4 29.4h12.6", .ground, 3, cap: .round)
        g.solid(knight, .ground, 2.6)
        g.stroke("M2.6 29.4h12.2", .ink, 1.2, cap: .round)
        g.fill("M3.6 29v-1.1c0-.6.4-1 1-1h8.2c.6 0 1 .4 1 1V29Z", .ink)
        g.solid(knight, .ink, 0.5)
        g.shade("M11.9 16.6 13.1 17.4M12.6 18.8l1.1.6M12.9 21l1 .5M12.8 23.2l.9.4")
        g.fill(g.disc(7.9, 17.2, c ? 0.8 : 0.65), .ground)
        if !c { g.stroke("M4 20.3c.3.2.6.2.9 0", .ground, 0.5, cap: .round) }
        // The jump: two ranks up, one file across.
        p.stroke("M22.25 10.4V7.25h-3.4", .accent, p.w(1.25), cap: .round, dash: [0.1, 2.1])
        p.fill("M16.4 7.25 18.6 5.6v3.3Z", .accent)
    }

    func play(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let body = "M3.6 28.2 5.2 14.6h21.6l1.6 13.6Z"
        p.solid(body, .ground, 2.6)
        if !c { p.stroke(p.hatch(CGRect(x: 4.5, y: 15.2, width: 23, height: 12.6), pitch: 1.6), .muted, 0.55, opacity: 0.6) }
        p.stroke(body, .ink, p.w(1.1), join: .round)
        p.stroke("M2.2 28.9h27.6", .ink, 1.2, cap: .round)
        // Buttons: the left one pressed, the right one up and running.
        p.stroke(p.rect(7.6, 12.4, 5.6, 2.2, 0.5), .ground, 1)
        p.fill(p.rect(7.6, 12.4, 5.6, 2.2, 0.5), .ink)
        p.stroke(p.rect(18.8, 9.8, 5.6, 4.8, 0.6), .ground, 1)
        p.fill(p.rect(18.8, 9.8, 5.6, 4.8, 0.6), .accent)
        if !c { p.stroke("M19.5 10.8h4.2", .ground, 0.5, cap: .round, opacity: 0.45) }
        // Dials.
        p.fill(p.disc(10.6, 21.6, 4.5), .ground)
        p.stroke(p.disc(10.6, 21.6, 4.5), .ink, p.w(1))
        p.fill(p.disc(21.4, 21.6, 4.5), .ground)
        p.stroke(p.disc(21.4, 21.6, 4.5), .accent, p.w(1.2))
        if !c {
            p.stroke(
                "M10.6 17.9v.8M10.6 24.5v.8M6.9 21.6h.8M13.5 21.6h.8M21.4 17.9v.8M21.4 24.5v.8M17.7 21.6h.8M24.3 21.6h.8",
                .muted, 0.6, cap: .round
            )
        }
        p.stroke("M10.6 21.6 8.7 19.9", .ink, p.w(0.9), cap: .round)
        p.stroke("M21.4 21.6 23.4 19.2", .accent, p.w(0.9), cap: .round)
        p.fill(p.disc(10.6, 21.6, 0.75), .ink)
        p.fill(p.disc(21.4, 21.6, 0.75), .accent)
    }

    func woodpecker(_ p: EmblemPen) {
        let c = p.compact
        let bird = "M16.4 8.4C17.2 6.2 19.2 4.9 21.6 5.1L25.2 3.9 23.9 6.5C25.2 7.8 25.7 9.8 25.3 11.8 26.8 13.6 27.8 16.6 27.8 20 27.8 22.6 27.2 24.6 26.5 26.1L28.2 31 25.6 28.9 24.7 30.8 23.8 27.7C21.4 26.6 19.6 24.4 19.2 21.4 18.8 18.4 19.4 15.8 18.6 13.6 17.6 12.6 16.7 11.7 16.3 10.7Z"
        p.plate()
        // The cycles: a tally on a1.
        if c {
            p.stroke("M5.6 20.4V24M7.6 20.4V24M9.6 20.4V24", .ink, 1, cap: .round, opacity: 0.8)
        } else {
            p.stroke("M5.2 20.2V24.2M6.8 20.2V24.2M8.4 20.2V24.2M10 20.2V24.2M4.4 23.4 10.6 20.8", .ink, 0.7, cap: .round, opacity: 0.85)
            // Chips flying from the struck square.
            p.stroke("M5.2 7.6 6.2 8.3M4.6 9.8H5.8M5.2 12 6.1 11.2", .ink, 0.6, cap: .round, opacity: 0.8)
        }
        p.solid(bird, .ground, 2.6)
        p.solid(bird, .ink, 0.4)
        if !c { p.stroke(p.hatch(circle: (21.6, 7.4, 2.3), pitch: 0.9), .ground, 0.35, opacity: 0.75) }
        // Eye and moustache stripe.
        p.fill(p.disc(19.4, 9.2, c ? 1.05 : 0.95), .ground)
        if !c { p.fill(p.disc(19.2, 9, 0.38), .ink) }
        p.stroke("M17 11C18.6 11.9 20.4 12.1 22.2 11.6", .ground, p.w(0.75), cap: .round)
        // Folded wing and the barring of the back.
        p.stroke("M22.4 14.2C24.6 16.4 25.4 20.6 24.6 25.4", .ground, p.w(0.7), cap: .round)
        if c {
            p.stroke("M25 16.6H27M25.2 19.6H27.4M25 22.6H26.8", .ground, 0.9, cap: .round)
        } else {
            p.stroke("M24.4 15.4 26.4 15M24.8 17.4 27.2 17M25 19.4 27.6 19M25 21.4 27.5 21.1M24.9 23.4 27 23.2", .ground, 0.6, cap: .round)
        }
        p.shade("M26.6 26.6 25.4 28.4M21.8 23.4 21 24.6M21.2 20.6 20.4 21.8")
        // Feet gripping the board's edge.
        let feet = "M19.3 22.2C18.6 22.3 18.1 22.7 17.8 23.3M19.5 23.7C18.8 23.9 18.4 24.3 18.1 24.9"
        p.stroke(feet, .ground, 1.8, cap: .round)
        p.stroke(feet, .ink, p.w(0.6), cap: .round)
        // The beak: a short brass chisel.
        let beak = "M16.6 8.4 8.6 9.6 16.3 10.8Z"
        p.solid(beak, .ground, 1.6)
        p.solid(beak, .accent, 0.5)
        if !c { p.stroke("M15.6 9.6H11.4", .ground, 0.4, cap: .round, opacity: 0.5) }
    }

    func coordinates(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // Rulers: below and to the right of the fragment.
        p.fill(p.rect(3.5, 27.4, 22.5, 3), .ground)
        p.stroke(p.rect(3.5, 27.4, 22.5, 3), .ink, p.w(1))
        p.fill(p.rect(27.4, 3.5, 3, 22.5), .ground)
        p.stroke(p.rect(27.4, 3.5, 3, 22.5), .ink, p.w(1))
        p.stroke(
            c ? "M11 27.4v1.6M18.5 27.4v1.6M27.4 11h1.6M27.4 18.5h1.6"
                : "M7.25 27.4v1M11 27.4v1.8M14.75 27.4v1M18.5 27.4v1.8M22.25 27.4v1M27.4 7.25h1M27.4 11h1.8M27.4 14.75h1M27.4 18.5h1.8M27.4 22.25h1",
            .ink, p.w(0.7)
        )
        if !c { p.stroke("M7.25 26.6V11.6M26.6 7.25H11.6", .ink, 0.6, dash: [1, 1.4], opacity: 0.6) }
        // The sight, on a3.
        p.fill(p.disc(7.25, 7.25, 3.4), .ground)
        p.stroke(p.disc(7.25, 7.25, 2.6), .accent, p.w(1.2))
        p.stroke("M7.25 3.2v2M7.25 9.3v2M3.2 7.25h2M9.3 7.25h2", .accent, p.w(0.9), cap: .round)
    }

    func analysis(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // The engine's line: a curved brass arrow.
        let line = "M11.2 23.6C9.4 18.8 10.2 13.6 13.2 9.4"
        p.stroke(line, .ground, 3.6, cap: .round)
        p.stroke(line, .accent, p.w(1.8), cap: .round)
        p.solid("M15.6 5.8 15 11.4 10.6 8.6Z", .accent, 0.6)
        // The evaluation bar, breaking the right edge.
        p.fill(p.rect(21.4, 2.2, 7, 27.6, 0.8), .ground)
        p.stroke(p.rect(21.4, 2.2, 7, 27.6, 0.8), .ground, 2.4)
        p.stroke(p.hatch(CGRect(x: 21.4, y: 2.2, width: 7, height: 10.6), pitch: c ? 2.2 : 1.4), .muted, p.w(0.6))
        p.fill(p.rect(21.4, 12.8, 7, 17), .ink)
        p.shade("M27.3 15v13.6", 0.7)
        p.stroke(p.rect(21.4, 2.2, 7, 27.6, 0.8), .ink, p.w(1.1))
        if !c { p.stroke("M19.6 12.8h1.2M29 12.8h1.2", .ink, 0.8, cap: .round) }
    }

    func explorer(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // The bow the compass hangs from.
        p.fill(p.disc(15, 4.4, 1.7), .ground)
        p.stroke(p.disc(15, 4.4, 1.7), .ink, p.w(1))
        // Dial cut out of the board.
        p.fill(p.disc(15, 16, 10.4), .ground)
        if !c {
            p.stroke(p.hatch(CGRect(x: 15, y: 16, width: 10, height: 10), circle: (15, 16, 8.2), pitch: 1.8), .muted, 0.5, opacity: 0.55)
        }
        p.stroke(p.disc(15, 16, 9.4), .ink, p.w(1.2))
        if !c { p.stroke(p.disc(15, 16, 8), .muted, 0.5) }
        p.stroke(
            c ? "M15 7.4v2M15 22.6v2M6.4 16h2M21.6 16h2"
                : "M15 6.9v2.2M15 22.9v2.2M5.9 16h2.2M21.9 16h2.2M21.4 9.6l-.8.8M8.6 9.6l.8.8M8.6 22.4l.8-.8M21.4 22.4l-.8-.8",
            .ink, p.w(0.8), cap: .round
        )
        // Needle: north in brass, south in ink.
        p.solid("M19.4 8.4 16.5 16.9 13.5 15.1Z", .accent, 0.5)
        p.solid("M10.6 23.6 13.5 15.1 16.5 16.9Z", .ink, 0.5)
        p.fill(p.disc(15, 16, 1.1), .ground)
        p.stroke(p.disc(15, 16, 1.1), .ink, 0.8)
        if !c { p.stroke("M8.2 11.2a8.4 8.4 0 0 1 4.6-4", .ink, 0.8, cap: .round, opacity: 0.75) }
        p.shade("M24.3 19.2a9.4 9.4 0 0 1-3.7 4.8", 0.7)
    }

    func nextMove(_ p: EmblemPen) {
        p.plate()
        // The arrow: from b1 to b3.
        p.stroke("M14.75 15.6V10.2", .ground, 4, cap: .round)
        p.stroke("M14.75 15.6V10.2", .accent, p.w(2), cap: .round)
        let head = "M14.75 3.6 18.3 9.4H11.2Z"
        p.solid(head, .ground, 1.6)
        p.solid(head, .accent, 0.6)
        // The pawn on b1, breaking the lower edge.
        let g = p.moved(14.75, 29.4)
        let body = "M-4.6-.4C-4.6-2.2-3.2-2.8-2-3.2-1.2-5-1.6-6.8-2.2-7.4H2.2C1.6-6.8 1.2-5 2-3.2 3.2-2.8 4.6-2.2 4.6-.4Z"
        g.stroke("M-6.2 0H6.2", .ground, 3, cap: .round)
        g.solid(body + "M-2.9-8.4H2.9V-7.3H-2.9Z", .ground, 2.6)
        g.fill(g.disc(0, -10.9, 2.7), .ground)
        g.stroke(g.disc(0, -10.9, 2.7), .ground, 2.6)
        g.stroke("M-5.8 0H5.8", .ink, 1.2, cap: .round)
        g.fill(body, .ink)
        g.fill(g.rect(-2.9, -8.5, 5.8, 1.2, 0.5), .ink)
        g.fill(g.disc(0, -10.9, 2.7), .ink)
        g.shade("M1.9-12.3a2.2 2.2 0 0 1-.9 3M3.1-2.4c.6.4 1 .9 1.1 1.5M1.1-6.4c-.1 1 0 2 .4 2.9")
    }

    func insights(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // Axes, breaking out left and below.
        p.stroke("M2.4 2.4V29.6H29.6", .ground, 3, cap: .round, join: .round)
        p.stroke("M2.4 2.4V29.6H29.6", .ink, p.w(1.1), cap: .round, join: .round)
        if !c {
            p.stroke("M.9 10h1.5M.9 17.5h1.5M.9 25h1.5M10 29.6v1.5M17.5 29.6v1.5M25 29.6v1.5", .ink, 0.7, cap: .round)
            p.stroke("M5 13.2H28", .ink, 0.6, dash: [1.2, 1.4], opacity: 0.6)
        }
        let line = "M5.4 24.6 10.8 19.2 15.2 21.6 20.6 12.8 27.4 7"
        p.stroke(line, .ground, 3.8, cap: .round, join: .round)
        p.stroke(line, .accent, p.w(1.7), cap: .round, join: .round)
        p.fill(p.disc(27.4, 7, 2.8), .ground)
        p.fill(p.disc(27.4, 7, 2.2), .accent)
    }

    func rating(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        // Dial cut out of the board.
        p.solid("M2.6 24.6A13.4 13.4 0 0 1 29.4 24.6Z", .ground, 2.4)
        if !c {
            p.stroke(p.hatch(CGRect(x: 16, y: 10, width: 14, height: 14.6), circle: (16, 24, 12.2), pitch: 1.8), .muted, 0.5, opacity: 0.5)
        }
        p.stroke("M3.4 24A12.6 12.6 0 0 1 28.6 24", .ink, p.w(1.2), cap: .round)
        var ticks = Path()
        let count = c ? 4 : 8
        for index in 0...count {
            let angle = Double.pi * (1 - Double(index) / Double(count))
            let inner: CGFloat = c || index % 2 == 0 ? 8.6 : 9.4
            ticks.move(to: CGPoint(x: 16 + inner * cos(angle), y: 24 - inner * sin(angle)))
            ticks.addLine(to: CGPoint(x: 16 + 10.6 * cos(angle), y: 24 - 10.6 * sin(angle)))
        }
        p.stroke(ticks, .ink, p.w(0.75), cap: .round)
        p.stroke("M1.8 24.6H30.2", .ink, p.w(1.2), cap: .round)
        if !c { p.stroke("M4.6 27.6h22.8", .ink, 0.6, cap: .round, opacity: 0.5) }
        // The needle.
        p.stroke("M16 24 22.6 13.6", .ground, 3.4, cap: .round)
        p.stroke("M16 24 22.6 13.6", .accent, p.w(1.5), cap: .round)
        p.fill(p.disc(16, 24, 2.8), .ground)
        p.fill(p.disc(16, 24, 2.3), .accent)
    }

    func theme(_ p: EmblemPen) {
        let c = p.compact
        let palette = "M4.4 18.2C4.4 10.8 10.4 5.6 17.6 5.6 24.2 5.6 28.6 9.4 28.6 14 28.6 17.6 26 18.4 23.4 18 21.4 17.7 19.9 19.4 20.6 21.4 21.6 24.4 20 28.4 14.6 28.4 8.6 28.4 4.4 24.2 4.4 18.2Z"
        p.plate()
        p.solid(palette, .ground, 2.6)
        p.stroke(palette, .ink, p.w(1.15), join: .round)
        p.stroke(p.disc(12.6, 22.4, 1.9), .ink, p.w(0.9))
        // Wells: light paint, dark paint (engraved), brass.
        p.fill(p.disc(10.4, 14.4, 2.3), .ink)
        p.stroke(p.disc(16.4, 10.2, 2.3), .ink, p.w(0.8))
        p.stroke(p.hatch(circle: (16.4, 10.2, 1.9), pitch: c ? 1.4 : 1), .ink, 0.55)
        p.fill(p.disc(23, 11.4, 2.4), .accent)
        p.shade("M6 19.6c.6 3.4 3.2 6.2 7.2 6.8M17 26.4c1.6-.8 2.4-2.2 2.2-3.8", 0.6)
        if !c { p.stroke("M22.4 15.6c1.6.5 3.4.4 4.6-.6", .muted, 0.6, cap: .round) }
    }

    func schedule(_ p: EmblemPen) {
        let c = p.compact
        let x0: CGFloat = 7.2
        let y0: CGFloat = 13.8
        let s: CGFloat = 3.6
        var days = Path()
        for i in 0..<5 {
            for j in 0..<4 where (i + j) % 2 == 1 && !(i == 3 && j == 2) {
                days.addPath(p.hatch(CGRect(x: x0 + CGFloat(i) * s, y: y0 + CGFloat(j) * s, width: s, height: s), pitch: c ? 1.8 : 1.2))
            }
        }
        p.plate()
        let leaf = p.rect(4.6, 7.4, 22.8, 21.6, 1.4)
        p.fill(leaf, .ground)
        p.stroke(leaf, .ground, 2.6)
        p.stroke(days, .muted, p.w(0.55))
        if !c { p.stroke(p.rect(x0, y0, 5 * s, 4 * s), .muted, 0.5) }
        // Header band and the leaf.
        p.fill("M4.6 12H27.4V8.8C27.4 8 26.8 7.4 26 7.4H6C5.2 7.4 4.6 8 4.6 8.8Z", .ink)
        p.stroke(leaf, .ink, p.w(1.15))
        p.shade("M26.4 14v13.8")
        // Rings.
        p.stroke("M10.6 4.2V9.6M21.4 4.2V9.6", .ground, 3.4, cap: .round)
        p.stroke("M10.6 4.2V9.6M21.4 4.2V9.6", .ink, p.w(1.3), cap: .round)
        // The day.
        p.stroke(p.disc(x0 + 3.5 * s, y0 + 2.5 * s, 2.9), .accent, p.w(1.3))
    }

    func importTray(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let tray = "M3 19.4 7.6 13.2H24.4L29 19.4V28.6H3Z"
        p.solid(tray, .ground, 2.6)
        if !c { p.stroke(p.hatch(CGRect(x: 3.6, y: 20, width: 24.8, height: 8), pitch: 1.6), .muted, 0.5, opacity: 0.6) }
        let lip = "M3 19.4H10.8C10.8 21.6 13 23.4 16 23.4S21.2 21.6 21.2 19.4H29"
        p.fill(lip, .ground)
        p.stroke(lip, .ink, p.w(1), join: .round)
        p.stroke(tray, .ink, p.w(1.15), join: .round)
        p.shade("M27.6 21v6.4")
        if !c { p.stroke("M9.4 16.2h13.2M8.2 17.8h15.6", .ink, 0.6, cap: .round, opacity: 0.6) }
        // The arrow.
        p.stroke("M16 2.6V13.4", .ground, 4, cap: .round)
        p.stroke("M16 2.6V12.6", .accent, p.w(2), cap: .round)
        let head = "M16 19.2 11.8 13.2H20.2Z"
        p.solid(head, .ground, 1.6)
        p.solid(head, .accent, 0.6)
    }

    func games(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let sheet = "M5.4 4.6H21.6V28.6H5.4Z"
        p.solid(sheet, .ground, 2.6)
        p.stroke(sheet, .ink, p.w(1.1), join: .round)
        p.stroke("M5.4 8.4H21.6M13.6 8.4V28.6", .ink, p.w(0.7), opacity: 0.7)
        p.stroke(
            c ? "M7.6 12.4h4M15.6 12.4h4M7.6 16.4h4M15.6 16.4h3.4M7.6 20.4h3.4"
                : "M7.6 11.6h4.2M15.6 11.6h3.8M7.6 14.4h3.6M15.6 14.4h4.2M7.6 17.2h4.2M15.6 17.2h3.2M7.6 20h3.8M15.6 20h4M7.6 22.8h2.8",
            .muted, p.w(0.75), cap: .round
        )
        if !c { p.stroke("M7.6 6.5h5.4", .ink, 0.7, cap: .round, opacity: 0.8) }
        p.shade("M20.6 10v17.6")
        // Pencil: brass body, ink point.
        p.stroke("M29 9.4 19.6 25.2", .ground, 5.2, cap: .round)
        p.stroke("M28.8 9.8 21.4 22.2", .accent, 2.8)
        if !c { p.stroke("M28.6 9.2 21.2 21.6", .ground, 0.5, opacity: 0.45) }
        p.solid("M22.6 22.9 20.2 21.5 19.4 25.7Z", .ink, 0.4)
    }

    func premium(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let ribbons = "M11.2 19.6 8.4 29.4 11.4 27.8 13.4 30.2 15.6 21.4ZM20.8 19.6 23.6 29.4 20.6 27.8 18.6 30.2 16.4 21.4Z"
        p.solid(ribbons, .ground, 2.4)
        p.solid(ribbons, .ink, 0.4)
        p.shade("M22.4 24.6l-1.6-.6M22.9 26.6l-1.6-.6")
        // The seal.
        p.fill(p.disc(16, 14, 10.2), .ground)
        p.fill(p.disc(16, 14, 9), .accent)
        if !c { p.stroke(p.disc(16, 14, 7.6), .ground, 0.5, opacity: 0.65) }
        p.solid("M10.8 17.6 10 10.8 13.4 13.6 16 9.2 18.6 13.6 22 10.8 21.2 17.6Z", .ground, 0.6)
        p.stroke("M11 19.2H21", .ground, p.w(1), cap: .round)
    }

    func tools(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        if !c { p.stroke("M8.6 22.4A13 13 0 0 0 23.4 22.4", .ink, 0.7, opacity: 0.7) }
        p.stroke("M16 7.4 7.4 29M16 7.4 24.6 29", .ground, 4.2, cap: .round)
        p.solid("M14.8 8.2 6.8 28.4 7.6 29.6 17.2 8.8ZM17.2 8.2 25.2 28.4 24.4 29.6 14.8 8.8Z", .ink, 0.6)
        p.shade("M18.4 12.2 23 23.8", 0.5)
        p.fill(p.disc(16, 7.6, 4), .ground)
        p.stroke("M16 1.8V4.4", .ground, 3.4, cap: .round)
        p.stroke("M16 1.8V4.6", .accent, p.w(1.6), cap: .round)
        p.fill(p.disc(16, 7.6, 3), .accent)
        p.fill(p.disc(16, 7.6, 0.9), .ground)
    }

    func settings(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        let rails = "M8 4.2V28.2M16 4.2V28.2M24 4.2V28.2"
        p.stroke(rails, .ground, 3.2, cap: .round)
        p.stroke(rails, .ink, p.w(1.1), cap: .round)
        for (knob, tone) in [(p.rect(4.6, 18.2, 6.8, 4.4, 1), EmblemPen.Tone.ink), (p.rect(20.6, 13.2, 6.8, 4.4, 1), .ink)] {
            p.stroke(knob, .ground, 1.4)
            p.fill(knob, tone)
        }
        p.shade("M5.6 21.6h4.8M21.6 16.6h4.8", 0.55)
        let lead = p.rect(12.6, 7.8, 6.8, 4.4, 1)
        p.stroke(lead, .ground, 1.4)
        p.fill(lead, .accent)
        if !c { p.stroke("M14 10h4", .ground, 0.6, cap: .round, opacity: 0.6) }
    }

    func profile(_ p: EmblemPen) {
        let c = p.compact
        p.plate()
        p.fill(p.ellipse(16, 15.8, 9.6, 12.2), .ground)
        if !c { p.stroke(p.hatch(circle: (16, 15.8, 8.4), pitch: 1.7), .muted, 0.45, opacity: 0.4) }
        // The king.
        p.stroke("M16 5.6V9.4M14.3 7.2H17.7", .ink, p.w(1.15), cap: .round)
        let head = "M11.8 13.4C11.8 11 13.7 9.8 16 9.8S20.2 11 20.2 13.4C20.2 14.8 19.4 15.6 18.8 16H13.2C12.6 15.6 11.8 14.8 11.8 13.4Z"
        p.solid(head, .ground, 1.6)
        p.fill(head, .ink)
        p.fill("M12.6 16.4H19.4V17.8H12.6ZM13.6 18.2C13.8 20.6 13.2 22.4 12 23.8H20C18.8 22.4 18.2 20.6 18.4 18.2ZM10.6 24.2H21.4V25.8H10.6Z", .ink)
        p.shade("M18.9 11.6c.4.6.6 1.2.5 2M17.2 19c0 1.6.4 3 1.2 4.2")
        p.stroke(p.ellipse(16, 15.8, 9.6, 12.2), .accent, p.w(1.5))
    }
}

#Preview("Emblems") {
    ScrollView {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: CD.Space.s20) {
            ForEach(Emblem.Kind.allCases, id: \.self) { kind in
                VStack(spacing: CD.Space.s8) {
                    Emblem(kind: kind, size: 56, surface: CD.canvas)
                    Emblem(kind: kind, size: 24, surface: CD.canvas)
                    Text(kind.rawValue).cdFont(.meta).foregroundStyle(CD.ink3)
                }
            }
        }
        .padding()
    }
    .background(CD.canvas)
}
