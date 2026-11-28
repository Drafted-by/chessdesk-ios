import SwiftUI

// Move-classification seals (`docs/design.md`, section 8), carried over from
// the site's `components/ui/move-glyph.tsx`: a flat disc in the colour of the
// class and a glyph in deep ink, never white, so it reads as a printed
// annotation rather than a glossy badge. Annotation marks (! ? !! ?? ?!) are
// drawn, not typeset: one 2.5 stroke with round caps and one 1.55 dot on a
// 24 grid. Always pair a seal with its label somewhere on screen.

extension CD {
    /// The calibrated palette of the classes (`--cd-cls-*`): similar
    /// lightness, so no class shouts louder than another.
    nonisolated enum Move {
        static let brilliant = Color(hex: 0x3ED0C8)
        static let great = Color(hex: 0x7CA9EC)
        static let best = Color(hex: 0x79C77C)
        static let good = Color(hex: 0x99B58B)
        static let book = Color(hex: 0xB8977C)
        static let inaccuracy = Color(hex: 0xE7C952)
        static let mistake = Color(hex: 0xED914C)
        static let blunder = Color(hex: 0xE85854)
        /// The glyph on a seal.
        static let ink = Color(hex: 0x16130F)
    }
}

nonisolated extension MoveClass {
    var color: Color {
        switch self {
        case .brilliant: CD.Move.brilliant
        case .great: CD.Move.great
        case .best: CD.Move.best
        case .good: CD.Move.good
        case .book: CD.Move.book
        case .inaccuracy: CD.Move.inaccuracy
        case .mistake: CD.Move.mistake
        case .blunder: CD.Move.blunder
        }
    }

    /// The classes a review points at: the moves worth stopping on.
    var isKeyMoment: Bool {
        switch self {
        case .brilliant, .great, .mistake, .blunder: true
        default: false
        }
    }

    /// Whether the move's SAN takes the colour of its class in a move list:
    /// inaccuracy and worse, brilliant and great; the rest stay ink.
    var coloursItsMove: Bool {
        switch self {
        case .inaccuracy, .mistake, .blunder, .brilliant, .great: true
        default: false
        }
    }
}

/// What a seal can show: a class of move, or a trainer's verdict.
nonisolated enum MoveGlyph: Hashable, Sendable {
    case move(MoveClass)
    /// The answer: a check on the best green.
    case right
    /// Not the answer: a cross on the blunder red.
    case wrong

    var color: Color {
        switch self {
        case let .move(kind): kind.color
        case .right: CD.Move.best
        case .wrong: CD.Move.blunder
        }
    }
}

struct MoveSeal: View {
    let glyph: MoveGlyph
    var size: CGFloat = 20
    /// Over a board: a ring in the page colour and a short shade set it off the squares.
    var onBoard = false

    init(_ kind: MoveClass, size: CGFloat = 20, onBoard: Bool = false) {
        glyph = .move(kind)
        self.size = size
        self.onBoard = onBoard
    }

    init(glyph: MoveGlyph, size: CGFloat = 20, onBoard: Bool = false) {
        self.glyph = glyph
        self.size = size
        self.onBoard = onBoard
    }

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 24, y: canvasSize.height / 24)
            if onBoard {
                context.fill(Self.disc(12, 12.9, 11.2), with: .color(.black.opacity(0.35)))
                context.fill(Self.disc(12, 12, 11.75), with: .color(CD.canvas))
            }
            context.fill(Self.disc(12, 12, 11), with: .color(glyph.color))
            // A hairline inner edge keeps the disc crisp on light squares, without gloss.
            context.stroke(Self.disc(12, 12, 10.6), with: .color(.black.opacity(0.16)), lineWidth: 0.8)
            draw(in: context)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private static let weight: CGFloat = 2.5
    private static let ink = GraphicsContext.Shading.color(CD.Move.ink)

    private static func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: 2 * radius, height: 2 * radius))
    }

    private static func stroke(_ context: GraphicsContext, _ data: String, width: CGFloat = weight) {
        context.stroke(Path(svg: data), with: ink, style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }

    /// "!" centred on x.
    private static func bang(_ context: GraphicsContext, _ x: CGFloat) {
        stroke(context, "M\(x) 6.6V12.9")
        context.fill(disc(x, 17.2, 1.55), with: ink)
    }

    /// "?" whose stem sits on x.
    private static func query(_ context: GraphicsContext, _ x: CGFloat) {
        stroke(context, "M\(x - 3.05) 9.05a3.05 3.05 0 1 1 4.35 2.75c-.85.42-1.3.98-1.3 1.9v.2")
        context.fill(disc(x, 17.2, 1.55), with: ink)
    }

    /// A context scaled about (x, 12), so paired marks keep one optical weight.
    private static func scaled(_ context: GraphicsContext, about x: CGFloat, by scale: CGFloat) -> GraphicsContext {
        var scaledContext = context
        scaledContext.translateBy(x: x, y: 12)
        scaledContext.scaleBy(x: scale, y: scale)
        scaledContext.translateBy(x: -x, y: -12)
        return scaledContext
    }

    private func draw(in context: GraphicsContext) {
        switch glyph {
        case .move(.brilliant):
            Self.bang(context, 9.4)
            Self.bang(context, 14.6)
        case .move(.great):
            Self.bang(context, 12)
        case .move(.best):
            let sparkle = Path(svg: "M12 5.6c.5 3.6 2.8 5.9 6.4 6.4-3.6.5-5.9 2.8-6.4 6.4-.5-3.6-2.8-5.9-6.4-6.4 3.6-.5 5.9-2.8 6.4-6.4z")
            context.fill(sparkle, with: Self.ink)
            context.stroke(sparkle, with: Self.ink, style: StrokeStyle(lineWidth: 1, lineJoin: .round))
        case .move(.good), .right:
            Self.stroke(context, "M7.7 12.4l2.9 2.9 5.7-6.2")
        case .move(.book):
            Self.stroke(
                context,
                "M12 8.4c-1.5-1.1-3.5-1.4-5.4-.9v8.6c1.9-.5 3.9-.2 5.4.9 1.5-1.1 3.5-1.4 5.4-.9V7.5c-1.9-.5-3.9-.2-5.4.9zM12 8.4v8.6",
                width: 1.9
            )
        case .move(.inaccuracy):
            Self.query(Self.scaled(context, about: 10.3, by: 0.86), 10.3)
            Self.bang(Self.scaled(context, about: 16.3, by: 0.86), 16.3)
        case .move(.mistake):
            Self.query(context, 12)
        case .move(.blunder):
            Self.query(Self.scaled(context, about: 7.8, by: 0.82), 7.8)
            Self.query(Self.scaled(context, about: 16.2, by: 0.82), 16.2)
        case .wrong:
            Self.stroke(context, "M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8")
        }
    }
}

#Preview("Move seals") {
    VStack(alignment: .leading, spacing: CD.Space.s12) {
        ForEach(MoveClass.allCases, id: \.self) { kind in
            HStack(spacing: CD.Space.s12) {
                MoveSeal(kind, size: 28)
                MoveSeal(kind, size: 16)
                Text(kind.label).cdFont(.body).foregroundStyle(CD.ink)
            }
        }
        HStack { MoveSeal(glyph: .right, size: 28, onBoard: true); MoveSeal(glyph: .wrong, size: 28, onBoard: true) }
    }
    .padding()
    .background(CD.canvas)
}
