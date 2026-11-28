import ChessCore
import SwiftUI

// The drawing layers shared by the interactive board and the static one.
// Squares come only from the board tokens; the linen weave shows through the
// checker (multiply), as on the site.

struct BoardSquaresLayer: View {
    let orientation: Side
    var showsCoordinates = false

    private var preferences: BoardPreferences { .shared }

    var body: some View {
        let light = preferences.lightSquare
        let dark = preferences.darkSquare
        ZStack {
            switch preferences.texture {
            case .plain:
                checker(light: light, dark: dark)
            case .fabric:
                // The fabric only lightly over the squares, so they stay clear.
                checker(light: light, dark: dark)
                texture("board-canvas")
                    .blendMode(.softLight)
                    .opacity(0.45)
            case .linen, .wood:
                texture(preferences.texture.imageName ?? "board-linen")
                checker(light: light, dark: dark)
                    .blendMode(.multiply)
            }
            if showsCoordinates {
                BoardCoordinatesLayer(orientation: orientation)
            }
        }
        .compositingGroup()
        .accessibilityHidden(true)
    }

    private func texture(_ name: String) -> some View {
        Image(name)
            .resizable()
            .interpolation(.medium)
    }

    private func checker(light: Color, dark: Color) -> some View {
        Canvas { context, size in
            let geometry = BoardGeometry(side: size.width, orientation: orientation)
            for square in Square.all {
                context.fill(Path(geometry.rect(of: square)), with: .color(square.isLight ? light : dark))
            }
        }
    }
}

/// File letters along the bottom edge and rank numbers along the left edge,
/// each in the opposite square colour.
private struct BoardCoordinatesLayer: View {
    let orientation: Side

    var body: some View {
        let light = BoardPreferences.shared.lightSquare
        let dark = BoardPreferences.shared.darkSquare
        return Canvas { context, size in
            let geometry = BoardGeometry(side: size.width, orientation: orientation)
            let fontSize = max(8, geometry.squareSize * 0.2)
            let inset = geometry.squareSize * 0.07
            let bottomRank = orientation == .white ? 0 : 7
            let leftFile = orientation == .white ? 0 : 7

            func label(_ text: String, on square: Square) -> GraphicsContext.ResolvedText {
                context.resolve(
                    Text(text)
                        .font(.custom("Geist-SemiBold", fixedSize: fontSize))
                        .foregroundStyle(square.isLight ? dark : light)
                )
            }

            for index in 0..<8 {
                if let square = Square(file: index, rank: bottomRank) {
                    let rect = geometry.rect(of: square)
                    context.draw(
                        label(String(square.description.prefix(1)), on: square),
                        at: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset),
                        anchor: .bottomTrailing
                    )
                }
                if let square = Square(file: leftFile, rank: index) {
                    let rect = geometry.rect(of: square)
                    context.draw(
                        label(String(square.description.suffix(1)), on: square),
                        at: CGPoint(x: rect.minX + inset, y: rect.minY + inset),
                        anchor: .topLeading
                    )
                }
            }
        }
    }
}

/// Square fills: last move, selection, check, verdict tint, hint ring and
/// the dots that mark where the selected piece can go.
struct BoardHighlightsLayer: View {
    let position: Position
    let orientation: Side
    var lastMove: Move?
    var selected: Square?
    var destinations: Set<Square> = []
    var verdict: BoardVerdict?
    var hint: Square?

    var body: some View {
        Canvas { context, size in
            let geometry = BoardGeometry(side: size.width, orientation: orientation)
            let unit = geometry.squareSize

            if let lastMove {
                for square in [lastMove.from, lastMove.to] {
                    context.fill(Path(geometry.rect(of: square)), with: .color(CD.Board.lastMove))
                }
            }
            if position.isCheck, let king = position.kingSquare(of: position.turn) {
                let rect = geometry.rect(of: king)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [CD.Board.check, CD.Board.check.opacity(0)]),
                        center: CGPoint(x: rect.midX, y: rect.midY),
                        startRadius: unit * 0.1,
                        endRadius: unit * 0.56
                    )
                )
            }
            if let verdict {
                context.fill(
                    Path(geometry.rect(of: verdict.square)),
                    with: .color(verdict.kind == .right ? CD.Board.right : CD.Board.wrong)
                )
            }
            if let selected {
                context.fill(Path(geometry.rect(of: selected)), with: .color(CD.Board.selected))
            }
            if let hint {
                let rect = geometry.rect(of: hint).insetBy(dx: unit * 0.04, dy: unit * 0.04)
                context.stroke(
                    Path(roundedRect: rect, cornerRadius: unit * 0.1),
                    with: .color(CD.Board.selected),
                    lineWidth: unit * 0.08
                )
            }
            for square in destinations {
                let center = geometry.center(of: square)
                if position[square] == nil {
                    let radius = unit * 0.16
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: center.x - radius, y: center.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(CD.Board.destination)
                    )
                } else {
                    // A capture: a ring around the piece instead of a dot under it.
                    let rect = geometry.rect(of: square).insetBy(dx: unit * 0.05, dy: unit * 0.05)
                    context.stroke(Path(ellipseIn: rect), with: .color(CD.Board.destination), lineWidth: unit * 0.09)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

struct BoardArrowsLayer: View {
    let arrows: [BoardArrow]
    let orientation: Side

    var body: some View {
        Canvas { context, size in
            let geometry = BoardGeometry(side: size.width, orientation: orientation)
            let unit = geometry.squareSize
            for arrow in arrows {
                let start = geometry.center(of: arrow.from)
                guard let target = arrow.to, target != arrow.from else {
                    let radius = unit * 0.42
                    context.stroke(
                        Path(ellipseIn: CGRect(
                            x: start.x - radius, y: start.y - radius,
                            width: radius * 2, height: radius * 2
                        )),
                        with: .color(arrow.brush.color),
                        lineWidth: unit * 0.075
                    )
                    continue
                }
                context.fill(Self.arrowPath(from: start, to: geometry.center(of: target), unit: unit),
                             with: .color(arrow.brush.color))
            }
        }
        // One translucent layer, so crossing arrows do not darken each other.
        .compositingGroup()
        .opacity(CD.Arrow.layerOpacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// A shaft that starts off the centre of its square and ends in a head.
    static func arrowPath(from start: CGPoint, to end: CGPoint, unit: CGFloat) -> Path {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = max(1, (dx * dx + dy * dy).squareRoot())
        let ux = dx / length
        let uy = dy / length
        let px = -uy
        let py = ux

        let shaft = unit * 0.078
        let headLength = unit * 0.42
        let headWidth = unit * 0.24
        let margin = unit * 0.28
        let tail = CGPoint(x: start.x + ux * margin, y: start.y + uy * margin)
        let neck = CGPoint(x: end.x - ux * headLength, y: end.y - uy * headLength)

        var path = Path()
        path.move(to: CGPoint(x: tail.x + px * shaft, y: tail.y + py * shaft))
        path.addLine(to: CGPoint(x: neck.x + px * shaft, y: neck.y + py * shaft))
        path.addLine(to: CGPoint(x: neck.x + px * headWidth, y: neck.y + py * headWidth))
        path.addLine(to: end)
        path.addLine(to: CGPoint(x: neck.x - px * headWidth, y: neck.y - py * headWidth))
        path.addLine(to: CGPoint(x: neck.x - px * shaft, y: neck.y - py * shaft))
        path.addLine(to: CGPoint(x: tail.x - px * shaft, y: tail.y - py * shaft))
        path.closeSubpath()
        return path
    }
}

/// The check or cross seal in the top corner of a verdict square.
struct VerdictSeal: View {
    let kind: BoardVerdict.Kind
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(kind == .right ? CD.Board.sealRight : CD.Board.sealWrong)
            Image(systemName: kind == .right ? "checkmark" : "xmark")
                .font(.system(size: size * 0.5, weight: .heavy))
                .foregroundStyle(Color.white)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(Color.black.opacity(0.25), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Any board nobody plays on: thumbnails, previews, empty states. Same
/// squares and the same piece drawings as the live board.
struct StaticBoardView: View {
    let fen: String
    var orientation: Side = .white
    var highlight: (from: Square, to: Square)?
    var cornerRadius: CGFloat = CD.Radius.sm

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = BoardGeometry(side: side, orientation: orientation)
            let position = Position(fen: fen)
            ZStack(alignment: .topLeading) {
                BoardSquaresLayer(orientation: orientation)
                if let highlight {
                    Canvas { context, _ in
                        for square in [highlight.from, highlight.to] {
                            context.fill(Path(geometry.rect(of: square)), with: .color(CD.Board.lastMove))
                        }
                    }
                }
                if let position {
                    ForEach(Square.all, id: \.self) { square in
                        if let piece = position[square] {
                            Image(piece.assetName)
                                .resizable()
                                .frame(width: geometry.squareSize, height: geometry.squareSize)
                                .offset(x: geometry.origin(of: square).x, y: geometry.origin(of: square).y)
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
