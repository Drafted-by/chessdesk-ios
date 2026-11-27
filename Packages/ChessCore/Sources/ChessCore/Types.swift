/// The two sides. `white` moves first.
public enum Side: String, Sendable, Hashable, CaseIterable, Codable {
    case white, black

    public var opposite: Side { self == .white ? .black : .white }
}

public enum PieceKind: Character, Sendable, Hashable, CaseIterable {
    case pawn = "p", knight = "n", bishop = "b", rook = "r", queen = "q", king = "k"

    /// The letter SAN uses for this piece ("" for a pawn).
    public var sanLetter: String {
        self == .pawn ? "" : String(rawValue).uppercased()
    }
}

public struct Piece: Sendable, Hashable {
    public let side: Side
    public let kind: PieceKind

    public init(_ side: Side, _ kind: PieceKind) {
        self.side = side
        self.kind = kind
    }

    /// FEN letter: uppercase for white.
    public var fenCharacter: Character {
        side == .white ? Character(String(kind.rawValue).uppercased()) : kind.rawValue
    }

    public init?(fenCharacter: Character) {
        guard let kind = PieceKind(rawValue: Character(fenCharacter.lowercased())) else { return nil }
        self.init(fenCharacter.isUppercase ? .white : .black, kind)
    }
}

/// A board square, a1 = 0, b1 = 1 … h8 = 63.
public struct Square: Sendable, Hashable, Comparable, CustomStringConvertible {
    public let index: Int

    public init(index: Int) {
        precondition((0..<64).contains(index), "square out of range")
        self.index = index
    }

    public init?(file: Int, rank: Int) {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        index = rank * 8 + file
    }

    /// Parses algebraic names such as "e4".
    public init?(_ name: some StringProtocol) {
        let scalars = Array(name.unicodeScalars)
        guard scalars.count == 2 else { return nil }
        let file = Int(scalars[0].value) - 97
        let rank = Int(scalars[1].value) - 49
        self.init(file: file, rank: rank)
    }

    public var file: Int { index % 8 }
    public var rank: Int { index / 8 }
    public var isLight: Bool { (file + rank) % 2 == 1 }

    public var description: String {
        "\(Character(UnicodeScalar(UInt8(97 + file))))\(rank + 1)"
    }

    public static func < (lhs: Square, rhs: Square) -> Bool { lhs.index < rhs.index }

    public static let all: [Square] = (0..<64).map(Square.init(index:))
}

public struct Move: Sendable, Hashable, CustomStringConvertible {
    public let from: Square
    public let to: Square
    public let promotion: PieceKind?

    public init(from: Square, to: Square, promotion: PieceKind? = nil) {
        self.from = from
        self.to = to
        self.promotion = promotion
    }

    /// Parses "e2e4" or "e7e8q".
    public init?(uci: some StringProtocol) {
        guard uci.count == 4 || uci.count == 5,
              let from = Square(uci.prefix(2)),
              let to = Square(uci.dropFirst(2).prefix(2))
        else { return nil }
        var promotion: PieceKind?
        if uci.count == 5 {
            guard let last = uci.last, let kind = PieceKind(rawValue: last),
                  kind != .pawn, kind != .king
            else { return nil }
            promotion = kind
        }
        self.init(from: from, to: to, promotion: promotion)
    }

    public var uci: String {
        "\(from)\(to)\(promotion.map { String($0.rawValue) } ?? "")"
    }

    public var description: String { uci }
}

public struct CastlingRights: OptionSet, Sendable, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let whiteKingside = CastlingRights(rawValue: 1)
    public static let whiteQueenside = CastlingRights(rawValue: 2)
    public static let blackKingside = CastlingRights(rawValue: 4)
    public static let blackQueenside = CastlingRights(rawValue: 8)
    public static let all: CastlingRights = [
        .whiteKingside, .whiteQueenside, .blackKingside, .blackQueenside,
    ]
}

public enum Outcome: Sendable, Hashable {
    case checkmate(winner: Side)
    case stalemate
    case insufficientMaterial
    case fiftyMoveRule
}
