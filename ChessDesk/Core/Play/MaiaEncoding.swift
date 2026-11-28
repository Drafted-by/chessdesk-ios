import ChessCore
import Foundation

/// What goes into the Maia-3 (5M) network and how its answer is read: a port
/// of the site's `apps/web/lib/play/engine/maia-encoding.ts`, itself a port
/// of the reference encoder of `CSSLab/maia3`.
///
/// The network always plays as White at the bottom. With Black to move the
/// board is mirrored (ranks flipped, colours swapped) before it is encoded,
/// and the policy is read in that mirrored frame.
nonisolated enum MaiaEncoding {
    static let history = 8
    static let planes = 12
    static let tokensPerSquare = history * planes
    static let policySize = 4352
    static let eloClampMax = 5000.0

    static let tokensName = "tokens"
    static let selfEloName = "self_elos"
    static let opponentEloName = "oppo_elos"
    static let policyName = "logits_move"

    private static let promotionKinds: [PieceKind] = [.queen, .rook, .bishop, .knight]

    private static func plane(of kind: PieceKind) -> Int {
        switch kind {
        case .pawn: 0
        case .knight: 1
        case .bishop: 2
        case .rook: 3
        case .queen: 4
        case .king: 5
        }
    }

    static func clampElo(_ elo: Double) -> Float {
        guard elo.isFinite else { return 0 }
        return Float(max(0, min(eloClampMax, elo.rounded())))
    }

    /// The three inputs of the network. `tokens` is 64 squares by 96 values:
    /// the 12-plane one-hot of the piece on each square, repeated over the 8
    /// history slots (the site sends no move history, so does the app).
    static func inputs(for position: Position, selfElo: Double, opponentElo: Double) -> [String: OnnxTensor] {
        let blackToMove = position.turn == .black
        var tokens = [Float](repeating: 0, count: 64 * tokensPerSquare)
        for square in Square.all {
            guard let piece = position[square] else { continue }
            let target = blackToMove ? square.index ^ 56 : square.index
            let side = blackToMove ? piece.side.opposite : piece.side
            let base = target * tokensPerSquare + plane(of: piece.kind) + (side == .black ? 6 : 0)
            for slot in 0..<history { tokens[base + slot * planes] = 1 }
        }
        return [
            tokensName: OnnxTensor(shape: [1, 64, tokensPerSquare], floats: tokens),
            selfEloName: OnnxTensor(shape: [1], floats: [clampElo(selfElo)]),
            opponentEloName: OnnxTensor(shape: [1], floats: [clampElo(opponentElo)]),
        ]
    }

    // MARK: The policy vocabulary

    /// Index of a move written in the mirrored frame: `from * 64 + to`, or
    /// 4096 and up for a promotion (always seventh to eighth rank there).
    static func policyIndex(uci: String) -> Int {
        let text = Array(uci.unicodeScalars)
        guard text.count >= 4 else { return -1 }
        func value(_ index: Int, _ base: UInt32) -> Int { Int(text[index].value) - Int(base) }
        if text.count == 4 {
            let from = value(1, 49) * 8 + value(0, 97)
            let to = value(3, 49) * 8 + value(2, 97)
            return from * 64 + to
        }
        guard let kind = PieceKind(rawValue: Character(text[4])), let piece = promotionKinds.firstIndex(of: kind) else { return -1 }
        return 4096 + value(0, 97) * 32 + value(2, 97) * 4 + piece
    }

    static func uci(policyIndex index: Int) -> String {
        func name(_ square: Int) -> String { Square(index: square).description }
        if index < 4096 { return name(index / 64) + name(index % 64) }
        let promotion = index - 4096
        let fromFile = Character(UnicodeScalar(UInt8(97 + promotion / 32)))
        let toFile = Character(UnicodeScalar(UInt8(97 + (promotion % 32) / 4)))
        return "\(fromFile)7\(toFile)8\(promotionKinds[promotion % 4].rawValue)"
    }

    /// The same move seen from the other side of the board.
    static func mirrored(_ uci: String) -> String {
        let text = Array(uci)
        guard text.count >= 4, let fromRank = text[1].wholeNumberValue, let toRank = text[3].wholeNumberValue else { return uci }
        return "\(text[0])\(9 - fromRank)\(text[2])\(9 - toRank)" + String(text.dropFirst(4))
    }

    // MARK: Choosing the move

    /// A legal move and the text the policy is asked about.
    struct Candidate: Equatable {
        let move: Move
        let uci: String
    }

    /// Every legal move, as the site lists them. Castling appears twice, once
    /// as the king's two-square move and once as "king takes rook": the site
    /// reads its legal moves from chessground's destinations, which hold both,
    /// and both are scored. The app keeps that so castling is as likely here.
    static func candidates(in position: Position) -> [Candidate] {
        var result: [Candidate] = []
        for move in position.legalMoves() {
            result.append(Candidate(move: move, uci: move.uci))
            if let rook = position.castlingRookMove(move) {
                result.append(Candidate(move: move, uci: "\(move.from)\(rook.from)"))
            }
        }
        return result
    }

    /// Chooses a legal move from the raw policy; never an illegal one.
    /// `temperature` 0 takes the best-scored legal move. Above 0 a move is
    /// drawn from the softmax over the legal moves, after the nucleus filter
    /// `topP` (keep the most likely moves until they sum to `topP`).
    static func decode(
        policy: [Float],
        position: Position,
        temperature: Double = 0,
        topP: Double = 1,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> Move? {
        let candidates = candidates(in: position)
        guard !candidates.isEmpty else { return nil }
        let blackToMove = position.turn == .black
        let scores: [Double] = candidates.map { candidate in
            let index = policyIndex(uci: blackToMove ? mirrored(candidate.uci) : candidate.uci)
            return index >= 0 && index < policy.count ? Double(policy[index]) : -.infinity
        }

        if temperature <= 0 {
            var best = 0
            for index in scores.indices where scores[index] > scores[best] { best = index }
            return candidates[best].move
        }

        let top = scores.max() ?? 0
        let weights = scores.map { $0 == -.infinity ? 0 : exp(($0 - top) / temperature) }
        let total = weights.reduce(0, +)
        var probabilities = weights.map { $0 / (total == 0 ? 1 : total) }

        if topP < 1 {
            let order = probabilities.indices.sorted { probabilities[$0] > probabilities[$1] }
            var kept = Set<Int>()
            var cumulative = 0.0
            for index in order {
                kept.insert(index)
                cumulative += probabilities[index]
                if cumulative >= topP { break }
            }
            let mass = probabilities.indices.reduce(0.0) { $0 + (kept.contains($1) ? probabilities[$1] : 0) }
            probabilities = probabilities.indices.map { kept.contains($0) ? probabilities[$0] / (mass == 0 ? 1 : mass) : 0 }
        }

        // The site walks every candidate; a draw of exactly 0 would then land
        // on the first one even when the filter removed it. Removed moves are
        // skipped here, which changes nothing for any other draw.
        var draw = random()
        var last = candidates[0].move
        for index in candidates.indices where probabilities[index] > 0 {
            last = candidates[index].move
            draw -= probabilities[index]
            if draw <= 0 { return last }
        }
        return last
    }
}
