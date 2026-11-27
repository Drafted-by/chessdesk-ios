import ChessCore
import SwiftUI

/// An annotation drawn over the board: an arrow, or a ring when `to` is nil.
struct BoardArrow: Hashable {
    enum Brush: String, Hashable {
        case move = "green", reply = "red", alternative = "blue", idea = "yellow"

        var color: Color {
            switch self {
            case .move: CD.Arrow.move
            case .reply: CD.Arrow.reply
            case .alternative: CD.Arrow.alternative
            case .idea: CD.Arrow.idea
            }
        }
    }

    let from: Square
    var to: Square?
    var brush: Brush = .move
}

/// The trainer's answer on the board: the square is tinted and carries a seal.
struct BoardVerdict: Hashable {
    enum Kind { case right, wrong }

    let square: Square
    let kind: Kind
}

/// Maps squares to points for one board size and orientation.
struct BoardGeometry {
    let side: CGFloat
    let orientation: Side

    var squareSize: CGFloat { side / 8 }

    func origin(of square: Square) -> CGPoint {
        let column = orientation == .white ? square.file : 7 - square.file
        let row = orientation == .white ? 7 - square.rank : square.rank
        return CGPoint(x: CGFloat(column) * squareSize, y: CGFloat(row) * squareSize)
    }

    func rect(of square: Square) -> CGRect {
        CGRect(origin: origin(of: square), size: CGSize(width: squareSize, height: squareSize))
    }

    func center(of square: Square) -> CGPoint {
        let origin = origin(of: square)
        return CGPoint(x: origin.x + squareSize / 2, y: origin.y + squareSize / 2)
    }

    func square(at point: CGPoint) -> Square? {
        guard point.x >= 0, point.y >= 0, point.x < side, point.y < side else { return nil }
        let column = Int(point.x / squareSize)
        let row = Int(point.y / squareSize)
        return orientation == .white
            ? Square(file: column, rank: 7 - row)
            : Square(file: 7 - column, rank: row)
    }
}

/// A piece on the board with an identity that survives moves, so SwiftUI can
/// animate it from one square to the next.
struct PlacedPiece: Identifiable, Equatable {
    let id: Int
    var piece: Piece
    var square: Square
}

enum PieceLayout {
    /// Re-uses the identities of `old` for the pieces of `position`: a piece
    /// that did not move keeps its id, a piece that appeared on a new square
    /// takes the id of the nearest unmatched piece of the same kind (it moved),
    /// and anything left is new.
    static func reconcile(_ old: [PlacedPiece], with position: Position, nextID: inout Int) -> [PlacedPiece] {
        var wanted: [Square: Piece] = [:]
        for square in Square.all {
            if let piece = position[square] { wanted[square] = piece }
        }

        var result: [PlacedPiece] = []
        var spare: [PlacedPiece] = []
        for placed in old {
            if wanted[placed.square] == placed.piece {
                result.append(placed)
                wanted[placed.square] = nil
            } else {
                spare.append(placed)
            }
        }

        for (square, piece) in wanted.sorted(by: { $0.key < $1.key }) {
            let candidates = spare.enumerated().filter { $0.element.piece == piece }
            if let nearest = candidates.min(by: {
                distance($0.element.square, square) < distance($1.element.square, square)
            }) {
                result.append(PlacedPiece(id: nearest.element.id, piece: piece, square: square))
                spare.remove(at: nearest.offset)
            } else {
                result.append(PlacedPiece(id: nextID, piece: piece, square: square))
                nextID += 1
            }
        }
        return result.sorted { $0.id < $1.id }
    }

    private static func distance(_ lhs: Square, _ rhs: Square) -> Int {
        abs(lhs.file - rhs.file) + abs(lhs.rank - rhs.rank)
    }
}

extension Piece {
    /// Asset name of the CBurnett drawing, e.g. "piece-wN".
    var assetName: String {
        "piece-\(side == .white ? "w" : "b")\(String(kind.rawValue).uppercased())"
    }

    var spokenName: String {
        let kindName = switch kind {
        case .pawn: "pawn"
        case .knight: "knight"
        case .bishop: "bishop"
        case .rook: "rook"
        case .queen: "queen"
        case .king: "king"
        }
        return "\(side == .white ? "white" : "black") \(kindName)"
    }
}
