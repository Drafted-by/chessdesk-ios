import ChessCore
import SwiftUI

/// The live board. It draws `position` and reports the move a player makes;
/// it never changes the position itself. The owner answers `onMove` with
/// `true` when it will show the result (a new position, or a wrong try held
/// on the board), `false` when the move is ignored and the piece goes home.
struct BoardView: View {
    let position: Position
    var orientation: Side = .white
    var lastMove: Move?
    var arrows: [BoardArrow] = []
    var verdict: BoardVerdict?
    /// A reviewed move: its seal in the corner of the square it landed on.
    var badge: BoardBadge?
    var hint: Square?
    /// The side that may move pieces; nil locks the board.
    var movableSide: Side?
    var showsCoordinates = true
    var onMove: (Move) -> Bool = { _ in false }

    @State private var pieces: [PlacedPiece] = []
    @State private var nextPieceID = 0
    @State private var selected: Square?
    @State private var drag: DragState?
    @State private var promotion: PendingPromotion?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct DragState: Equatable {
        let pieceID: Int
        let from: Square
        var location: CGPoint
        var moved: Bool
        /// The piece was already selected when the finger came down: lifting
        /// without moving deselects it.
        let wasSelected: Bool
    }

    private struct PendingPromotion: Equatable {
        let from: Square
        let to: Square
    }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let geometry = BoardGeometry(side: side, orientation: orientation)
            ZStack(alignment: .topLeading) {
                BoardSquaresLayer(orientation: orientation, showsCoordinates: showsCoordinates)
                BoardHighlightsLayer(
                    position: position,
                    orientation: orientation,
                    lastMove: lastMove,
                    selected: selected,
                    destinations: destinations,
                    verdict: verdict,
                    hint: hint
                )
                piecesLayer(geometry)
                BoardArrowsLayer(arrows: arrows, orientation: orientation)
                if let verdict {
                    let rect = geometry.rect(of: verdict.square)
                    let seal = geometry.squareSize * 0.36
                    VerdictSeal(kind: verdict.kind, size: seal)
                        .offset(x: rect.maxX - seal * 0.78, y: rect.minY - seal * 0.22)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                if let badge {
                    let rect = geometry.rect(of: badge.square)
                    let seal = geometry.squareSize * 0.42
                    MoveSeal(badge.kind, size: seal, onBoard: true)
                        // Inside the board on the last file and the first rank shown.
                        .offset(
                            x: min(rect.maxX - seal * 0.72, side - seal),
                            y: max(rect.minY - seal * 0.28, 0)
                        )
                        .id(badge)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                        .allowsHitTesting(false)
                }
                if let promotion {
                    promotionPicker(promotion, geometry)
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(boardGesture(geometry))
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: position, initial: true) { _, newValue in
            sync(to: newValue, animated: !pieces.isEmpty)
        }
        .onChange(of: movableSide) { _, _ in
            selected = nil
            promotion = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: Pieces

    private func piecesLayer(_ geometry: BoardGeometry) -> some View {
        ForEach(pieces) { placed in
            let dragging = drag?.pieceID == placed.id && drag?.moved == true
            let origin = geometry.origin(of: placed.square)
            Image(placed.piece.assetName)
                .resizable()
                .frame(width: geometry.squareSize, height: geometry.squareSize)
                .scaleEffect(dragging ? 1.7 : 1)
                .shadow(color: .black.opacity(dragging ? 0.35 : 0), radius: 6, y: 4)
                .offset(
                    x: dragging ? (drag?.location.x ?? 0) - geometry.squareSize / 2 : origin.x,
                    y: dragging ? (drag?.location.y ?? 0) - geometry.squareSize * 1.1 : origin.y
                )
                .zIndex(dragging ? 2 : 1)
        }
    }

    private func sync(to position: Position, animated: Bool) {
        var id = nextPieceID
        let next = PieceLayout.reconcile(pieces, with: position, nextID: &id)
        nextPieceID = id
        selected = nil
        promotion = nil
        if animated, !reduceMotion {
            withAnimation(CD.Motion.pieceMove) { pieces = next }
        } else {
            pieces = next
        }
    }

    private var destinations: Set<Square> {
        guard let selected else { return [] }
        return Set(position.legalMoves(from: selected).map(\.to))
    }

    private func canMove(_ square: Square) -> Bool {
        guard let movableSide, position.turn == movableSide else { return false }
        return position[square]?.side == movableSide
    }

    // MARK: Gestures

    private func boardGesture(_ geometry: BoardGeometry) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard promotion == nil else { return }
                if var current = drag {
                    current.location = value.location
                    if !current.moved {
                        let distance = hypot(value.translation.width, value.translation.height)
                        current.moved = distance > 6
                    }
                    drag = current
                    return
                }
                guard let square = geometry.square(at: value.startLocation), canMove(square),
                      let placed = pieces.first(where: { $0.square == square })
                else { return }
                drag = DragState(
                    pieceID: placed.id,
                    from: square,
                    location: value.location,
                    moved: false,
                    wasSelected: selected == square
                )
                selected = square
            }
            .onEnded { value in
                guard promotion == nil else { return }
                let target = geometry.square(at: value.location)
                if let current = drag {
                    drag = nil
                    if current.moved {
                        drop(from: current.from, on: target, pieceID: current.pieceID)
                    } else if current.wasSelected {
                        selected = nil
                    }
                    return
                }
                tap(on: target)
            }
    }

    private func tap(on target: Square?) {
        guard let target, let from = selected, destinations.contains(target) else {
            selected = nil
            return
        }
        attempt(from: from, to: target)
    }

    private func drop(from: Square, on target: Square?, pieceID: Int) {
        guard let target, destinations.contains(target) else { return }
        // The piece is already under the finger: place it without a slide.
        if let index = pieces.firstIndex(where: { $0.id == pieceID }) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { pieces[index].square = target }
        }
        attempt(from: from, to: target)
    }

    private func attempt(from: Square, to: Square) {
        let candidates = position.legalMoves(from: from).filter { $0.to == to }
        if candidates.count > 1 {
            promotion = PendingPromotion(from: from, to: to)
            return
        }
        guard let move = candidates.first else { return }
        commit(move)
    }

    private func commit(_ move: Move) {
        selected = nil
        promotion = nil
        if !onMove(move) {
            sync(to: position, animated: true)
        }
    }

    // MARK: Promotion

    private func promotionPicker(_ pending: PendingPromotion, _ geometry: BoardGeometry) -> some View {
        let unit = geometry.squareSize
        let kinds: [PieceKind] = [.queen, .knight, .rook, .bishop]
        let column = geometry.origin(of: pending.to).x
        let fromTop = geometry.origin(of: pending.to).y < geometry.side / 2
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.35)
                .onTapGesture {
                    promotion = nil
                    sync(to: position, animated: true)
                }
            VStack(spacing: 0) {
                ForEach(fromTop ? kinds : kinds.reversed(), id: \.self) { kind in
                    Button {
                        commit(Move(from: pending.from, to: pending.to, promotion: kind))
                    } label: {
                        Image(Piece(position.turn, kind).assetName)
                            .resizable()
                            .frame(width: unit, height: unit)
                    }
                    .buttonStyle(CDPressStyle())
                    .accessibilityLabel("Promote to \(Piece(position.turn, kind).spokenName)")
                }
            }
            .background(CD.surface2)
            .clipShape(RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 10, y: 4)
            .offset(x: column, y: fromTop ? 0 : geometry.side - unit * 4)
        }
        .zIndex(3)
    }

    private var accessibilitySummary: String {
        let turn = position.turn == .white ? "White" : "Black"
        if position.isCheckmate { return "Chess board. Checkmate." }
        return "Chess board. \(turn) to move\(position.isCheck ? ", in check" : "")."
    }
}
