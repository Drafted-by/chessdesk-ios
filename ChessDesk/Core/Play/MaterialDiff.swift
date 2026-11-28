import ChessCore
import Foundation

/// What each side has taken and who is ahead, as the bars above and below a
/// board show it. Read from the position against the starting set, never
/// from a list of captures, so it stays right after a promotion and for any
/// position on screen. A port of the site's `lib/play/material.ts`.
nonisolated struct MaterialDiff: Hashable, Sendable {
    struct Group: Hashable, Sendable {
        let kind: PieceKind
        let count: Int
    }

    struct SideMaterial: Hashable, Sendable {
        /// The opponent's pieces this side has captured, pawn first, queen last.
        let captured: [Group]
        /// Lead in pawns (P1 N3 B3 R5 Q9); 0 unless this side is ahead.
        let advantage: Int
    }

    let white: SideMaterial
    let black: SideMaterial

    subscript(side: Side) -> SideMaterial { side == .white ? white : black }

    static let captureOrder: [PieceKind] = [.pawn, .knight, .bishop, .rook, .queen]

    static func value(of kind: PieceKind) -> Int {
        switch kind {
        case .pawn: 1
        case .knight, .bishop: 3
        case .rook: 5
        case .queen: 9
        case .king: 0
        }
    }

    private static func startCount(of kind: PieceKind) -> Int {
        switch kind {
        case .pawn: 8
        case .knight, .bishop, .rook: 2
        case .queen: 1
        case .king: 1
        }
    }

    init(position: Position) {
        var counts: [Side: [PieceKind: Int]] = [.white: [:], .black: [:]]
        for square in Square.all {
            guard let piece = position[square], piece.kind != .king else { continue }
            counts[piece.side, default: [:]][piece.kind, default: 0] += 1
        }
        func material(_ side: Side) -> Int {
            Self.captureOrder.reduce(0) { $0 + (counts[side]?[$1] ?? 0) * Self.value(of: $1) }
        }
        /// Pieces of one side missing from the starting set. A piece above
        /// its starting count came from a promoted pawn, so that pawn left
        /// the board without being captured.
        func missing(_ side: Side) -> [Group] {
            let own = counts[side] ?? [:]
            let promoted = Self.captureOrder.filter { $0 != .pawn }
                .reduce(0) { $0 + max(0, (own[$1] ?? 0) - Self.startCount(of: $1)) }
            return Self.captureOrder.compactMap { kind in
                let gone = Self.startCount(of: kind) - (own[kind] ?? 0) - (kind == .pawn ? promoted : 0)
                return gone > 0 ? Group(kind: kind, count: gone) : nil
            }
        }
        let lead = material(.white) - material(.black)
        white = SideMaterial(captured: missing(.black), advantage: max(0, lead))
        black = SideMaterial(captured: missing(.white), advantage: max(0, -lead))
    }
}
