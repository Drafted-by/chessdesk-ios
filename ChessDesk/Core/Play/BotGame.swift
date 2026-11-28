import ChessCore
import Foundation

/// Where a bot game starts: a position, plus the moves that led there (kept
/// so the saved game is whole, not just the continuation). A port of the
/// site's `lib/play/start-position.ts`.
nonisolated struct BotStart: Codable, Hashable, Sendable {
    /// FEN of the first position of the game.
    var fen = Position.startFEN
    /// Moves already played before the bot game begins, in UCI.
    var moves: [String] = []

    static let standard = BotStart()

    var isStandard: Bool { fen == Position.startFEN && moves.isEmpty }

    /// The side to move once the preset moves are played.
    var turn: Side { game?.position.turn ?? .white }

    var game: Game? {
        Position(fen: fen).flatMap { Game(start: $0, uciMoves: moves) }
    }

    enum ParseError: Error, Equatable {
        case empty, tooLong, illegalFEN, noMoves, alreadyFinished

        var message: String {
            switch self {
            case .empty: "Paste a FEN or a PGN."
            case .tooLong: "That PGN is too long."
            case .illegalFEN: "That FEN is not a legal position."
            case .noMoves: "No moves found. Paste a FEN or a PGN with moves."
            case .alreadyFinished: "That position is already finished. Pick one with moves left to play."
            }
        }
    }

    private static let maxInput = 100_000

    /// Reads what a player pasted: a FEN, or a PGN whose main line is
    /// replayed (variations and comments are dropped). An illegal setup and a
    /// position that is already over are refused.
    static func parse(_ input: String) -> Result<BotStart, ParseError> {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .failure(.empty) }
        if text.count > maxInput { return .failure(.tooLong) }

        var start: BotStart
        if looksLikeFEN(text) {
            // A bare placement, or a FEN without its counters, is completed.
            let parts = text.split(whereSeparator: \.isWhitespace).map(String.init)
            func part(_ index: Int, _ fallback: String) -> String { index < parts.count ? parts[index] : fallback }
            let fen = [parts[0], part(1, "w"), part(2, "-"), part(3, "-"), part(4, "0"), part(5, "1")].joined(separator: " ")
            guard let position = Position(fen: fen), position.isPlayableSetup else { return .failure(.illegalFEN) }
            start = BotStart(fen: position.fen, moves: [])
        } else {
            let line = GameLine(pgn: text)
            if line.moves.isEmpty, line.startFEN == Position.startFEN { return .failure(.noMoves) }
            start = BotStart(fen: line.startFEN, moves: line.moves.map(\.move.uci))
        }
        guard let game = start.game else { return .failure(.illegalFEN) }
        if game.boardEnding != nil { return .failure(.alreadyFinished) }
        return .success(start)
    }

    /// True for a single line of eight valid ranks; a PGN is anything else.
    static func looksLikeFEN(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains(where: \.isNewline) || trimmed.hasPrefix("[") { return false }
        if trimmed.range(of: #"\b\d+\.\s"#, options: .regularExpression) != nil { return false }
        let rows = (trimmed.split(whereSeparator: \.isWhitespace).first ?? "").split(separator: "/", omittingEmptySubsequences: false)
        guard rows.count == 8 else { return false }
        return rows.allSatisfy { row in
            var squares = 0
            for character in row {
                if let skip = character.wholeNumberValue, (1...8).contains(skip) {
                    squares += skip
                } else if "pnbrqkPNBRQK".contains(character) {
                    squares += 1
                } else {
                    return false
                }
            }
            return squares == 8
        }
    }
}

/// What a game against a bot is made of, decided before the first move.
nonisolated struct BotGameSetup: Codable, Hashable, Sendable {
    /// The roster id, or "custom" for a built opponent.
    var botID: String
    var botName: String
    var rating: Int
    /// Portrait: a path on the site or a full URL.
    var avatar: String
    var country: String?
    var humanSide: Side
    /// The move the bot likes to open with as White, in UCI.
    var firstMove: String?
    /// How loosely Maia samples for this opponent, as the catalogue gave it
    /// when the game was set up.
    var temperature: Double
    /// The `UCI_Elo` Stockfish is held to for this opponent, from the catalogue.
    var stockfishElo: Int
    /// True for "build your own opponent": its rating is sent when saving.
    var isCustom = false
    var start = BotStart.standard

    var strength: BotStrength {
        BotStrength(rating: rating, temperature: temperature, stockfishElo: stockfishElo)
    }
}

/// A game against a bot: the moves, whose turn it is, and how it ended. A
/// value with no engine and no clock inside, so the whole game can be tested
/// and stored. The rules are ChessCore's; the flow is a port of the site's
/// `components/play/use-bot-game.ts`.
nonisolated struct BotGame: Hashable, Sendable {
    let setup: BotGameSetup
    private(set) var game: Game
    private(set) var resigned = false

    /// Nil when the start cannot be replayed (a stored game from rules that changed).
    init?(setup: BotGameSetup) {
        guard let game = setup.start.game else { return nil }
        self.setup = setup
        self.game = game
    }

    var position: Position { game.position }
    var moves: [PlayedMove] { game.moves }
    var lastMove: Move? { game.moves.last?.move }
    var humanSide: Side { setup.humanSide }
    var botSide: Side { setup.humanSide.opposite }

    // MARK: How it stands

    /// How the game ended, or nil while it is played. As on the site, a
    /// draw that could be claimed (the third occurrence of a position, fifty
    /// moves without a capture or a pawn move) ends the game at once.
    var termination: BotGameTermination? {
        if resigned { return .resignation }
        return game.ending(claimingDraws: true).map(BotGameTermination.init)
    }

    var isOver: Bool { termination != nil }

    /// "1-0", "0-1" or "1/2-1/2"; nil while the game is played.
    var result: String? {
        if resigned { return humanSide == .white ? "0-1" : "1-0" }
        guard let ending = game.ending(claimingDraws: true) else { return nil }
        guard let winner = ending.winner else { return "1/2-1/2" }
        return winner == .white ? "1-0" : "0-1"
    }

    var outcome: BotGameOutcome? {
        termination.map { BotGameOutcome(result: result, termination: $0, humanSide: humanSide) }
    }

    var humanToMove: Bool { !isOver && position.turn == humanSide }
    var botToMove: Bool { !isOver && position.turn == botSide }

    // MARK: Moves

    /// The player's move. Refused when it is not their turn, when the game is
    /// over, or when the move is not legal.
    @discardableResult
    mutating func playHuman(_ move: Move) -> PlayedMove? {
        guard humanToMove else { return nil }
        return play(move)
    }

    /// The bot's signature opening move, when it applies: its very first
    /// move as White, from the standard start, and only if it is legal.
    var signatureMove: Move? {
        guard humanSide == .black, game.moves.isEmpty, setup.start.isStandard,
              let move = setup.firstMove.flatMap({ Move(uci: $0) }), position.isLegal(move)
        else { return nil }
        return move
    }

    /// The bot's move, from what its engine answered. An answer that is not
    /// a legal move (or no answer at all) never freezes the game: a random
    /// legal move is played instead. Nil when it is not the bot's turn.
    @discardableResult
    mutating func playBot(
        answer uci: String?,
        random: (Range<Int>) -> Int = { Int.random(in: $0) }
    ) -> PlayedMove? {
        guard botToMove else { return nil }
        if let move = uci.flatMap({ Move(uci: $0) }), let played = play(move) { return played }
        let legal = position.legalMoves()
        guard !legal.isEmpty else { return nil }
        return play(legal[random(0..<legal.count)])
    }

    private mutating func play(_ move: Move) -> PlayedMove? {
        guard !isOver else { return nil }
        let current = position
        // A pawn reaching the last rank without a piece named becomes a queen.
        if let played = game.play(move) { return played }
        if move.promotion == nil, current[move.from]?.kind == .pawn, move.to.rank == 0 || move.to.rank == 7 {
            return game.play(Move(from: move.from, to: move.to, promotion: .queen))
        }
        return nil
    }

    mutating func resign() {
        guard !isOver else { return }
        resigned = true
    }

    // MARK: The game as text

    /// The whole game as PGN, the preset moves included.
    func pgn(humanName: String) -> String {
        game.pgn(tags: [
            "Event": "Bot game",
            "White": humanSide == .white ? humanName : setup.botName,
            "Black": humanSide == .white ? setup.botName : humanName,
            "Result": result ?? "*",
        ])
    }

    /// What `POST /api/v1/play/games` takes for a finished game. The server
    /// reads the bot's name and rating from its catalogue; only the custom
    /// bot's rating is the player's choice, so only that one is sent.
    func saveRequest(humanName: String, engine: BotEngineKind) -> SaveBotGameRequest {
        SaveBotGameRequest(
            bot: setup.botID,
            rating: setup.isCustom ? setup.rating : nil,
            userColor: humanSide.rawValue,
            result: result ?? "1/2-1/2",
            engine: engine.rawValue,
            pgn: pgn(humanName: humanName)
        )
    }
}

// MARK: Keeping a game

/// A game as it is written to disk: what it was set up with and every move
/// since its first position. Reading it back replays the moves through the
/// rules, so a file that does not make a legal game is dropped.
nonisolated struct BotGameSnapshot: Codable, Hashable, Sendable {
    var setup: BotGameSetup
    /// Every move from `setup.start.fen`, preset moves included, in UCI.
    var moves: [String]
    var resigned = false
    /// The engine that has played the bot's moves.
    var engine: BotEngineKind
    var savedAt = Date.now

    init(_ game: BotGame, engine: BotEngineKind, now: Date = .now) {
        setup = game.setup
        moves = game.moves.map(\.move.uci)
        resigned = game.resigned
        self.engine = engine
        savedAt = now
    }

    func restored() -> BotGame? {
        guard var game = BotGame(setup: setup), moves.count >= setup.start.moves.count,
              Array(moves.prefix(setup.start.moves.count)) == setup.start.moves
        else { return nil }
        for text in moves.dropFirst(setup.start.moves.count) {
            guard let move = Move(uci: text), game.replay(move) else { return nil }
        }
        if resigned { game.resign() }
        return game
    }
}

nonisolated extension BotGame {
    /// Replays a stored move for whichever side is to move.
    fileprivate mutating func replay(_ move: Move) -> Bool {
        guard !isOver else { return false }
        return game.play(move) != nil
    }
}
