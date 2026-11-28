import ChessCore
import Foundation

/// How a bot game ended. Raw values are the site's (`lib/play/outcome.ts`).
nonisolated enum BotGameTermination: String, Codable, Hashable, Sendable {
    case checkmate
    case resignation
    case timeout
    case stalemate
    case repetition
    case fiftyMove = "fifty-move"
    case insufficientMaterial = "insufficient-material"
    case agreement

    var isDraw: Bool {
        switch self {
        case .stalemate, .repetition, .fiftyMove, .insufficientMaterial, .agreement: true
        case .checkmate, .resignation, .timeout: false
        }
    }

    init(_ ending: GameEnding) {
        switch ending {
        case .checkmate: self = .checkmate
        case .stalemate: self = .stalemate
        case .insufficientMaterial: self = .insufficientMaterial
        case .threefoldRepetition: self = .repetition
        case .fiftyMoveRule: self = .fiftyMove
        }
    }
}

/// How a finished bot game reads, from the player's side of the board. One
/// place for every end-of-game sentence, so the board, the summary and the
/// opponent's line never disagree. A port of the site's `lib/play/outcome.ts`.
nonisolated struct BotGameOutcome: Hashable, Sendable {
    enum Tone: Hashable, Sendable { case win, loss, draw }

    let tone: Tone
    let termination: BotGameTermination
    /// "1-0", "0-1" or "1/2-1/2".
    let result: String
    let humanSide: Side

    /// A drawn termination always scores ½–½; a decisive one needs the result.
    init(result: String?, termination: BotGameTermination, humanSide: Side) {
        self.humanSide = humanSide
        guard !termination.isDraw, let result, result != "1/2-1/2" else {
            tone = .draw
            self.termination = termination.isDraw ? termination : .agreement
            self.result = "1/2-1/2"
            return
        }
        let humanWon = (result == "1-0") == (humanSide == .white)
        tone = humanWon ? .win : .loss
        self.termination = termination
        self.result = result
    }

    /// Number of the last move played ("in 9 moves"), from its ply.
    static func moveNumber(ofPly ply: Int) -> Int {
        max(1, (ply + 1) / 2)
    }

    private static func inMoves(_ count: Int?) -> String {
        guard let count, count > 0 else { return "" }
        return " in \(count) \(count == 1 ? "move" : "moves")"
    }

    /// The title over the board: the event first, then what it means for you.
    func title(botName: String) -> String {
        if tone == .draw {
            switch termination {
            case .stalemate: return "Stalemate — a draw"
            case .repetition: return "Draw by repetition"
            case .fiftyMove: return "Draw by the 50-move rule"
            case .insufficientMaterial: return "Draw — insufficient material"
            default: return "Draw agreed"
            }
        }
        let won = tone == .win
        switch termination {
        case .checkmate: return won ? "Checkmate — you won" : "Checkmate — you lost"
        case .resignation: return won ? "\(botName) resigned — you won" : "You resigned"
        case .timeout: return won ? "\(botName) ran out of time — you won" : "Out of time — you lost"
        default: return won ? "You won" : "You lost"
        }
    }

    /// The short headline of the summary; the method goes below it.
    var headline: String {
        if tone == .draw { return "Draw" }
        if tone == .loss, termination == .resignation { return "You resigned" }
        return tone == .win ? "You won" : "You lost"
    }

    /// "by checkmate in 9 moves", "on time", "by threefold repetition".
    func terminationPhrase(lastMoveNumber: Int? = nil) -> String {
        switch termination {
        case .checkmate: return "by checkmate\(Self.inMoves(lastMoveNumber))"
        case .resignation:
            guard let lastMoveNumber, lastMoveNumber > 0 else { return "by resignation" }
            return "by resignation after \(lastMoveNumber) \(lastMoveNumber == 1 ? "move" : "moves")"
        case .timeout: return "on time"
        case .stalemate: return "by stalemate"
        case .repetition: return "by threefold repetition"
        case .fiftyMove: return "by the 50-move rule"
        case .insufficientMaterial: return "by insufficient material"
        case .agreement: return "by agreement"
        }
    }

    /// One word for how it ended, for a compact row.
    var terminationName: String {
        switch termination {
        case .checkmate: "Checkmate"
        case .resignation: "Resignation"
        case .timeout: "Time"
        case .stalemate: "Stalemate"
        case .repetition: "Repetition"
        case .fiftyMove: "50-move rule"
        case .insufficientMaterial: "Insufficient material"
        case .agreement: "Agreement"
        }
    }

    /// The line under the bot's name, written from the bot's side: it reads
    /// "Checkmated" when you won.
    var botStatusLine: String {
        if tone == .draw { return "Drew \(terminationPhrase())" }
        let botWon = tone == .loss
        switch termination {
        case .checkmate: return botWon ? "Won by checkmate" : "Checkmated"
        case .resignation: return botWon ? "Won by resignation" : "Resigned"
        case .timeout: return botWon ? "Won on time" : "Lost on time"
        default: return botWon ? "Won" : "Lost"
        }
    }

    /// The closing line under the moves, as printed at the end of a game score.
    var scoreSheetEnding: String {
        if tone == .draw { return "Draw \(terminationPhrase())" }
        let winner = result == "1-0" ? "White" : "Black"
        switch termination {
        case .checkmate: return "\(winner) wins by checkmate"
        case .resignation: return "\(result == "1-0" ? "Black" : "White") resigns"
        case .timeout: return "\(winner) wins on time"
        default: return "\(winner) wins"
        }
    }

    /// "1–0", "0–1", "½–½".
    static func printedScore(_ result: String) -> String {
        result == "1/2-1/2" ? "½–½" : result.replacingOccurrences(of: "-", with: "–")
    }
}
