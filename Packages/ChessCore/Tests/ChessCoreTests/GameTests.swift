import Testing
@testable import ChessCore

@Suite struct GameTests {
    private func game(_ moves: String, from fen: String = Position.startFEN) throws -> Game {
        let start = try #require(Position(fen: fen))
        return try #require(Game(start: start, uciMoves: moves.split(separator: " ").map(String.init)))
    }

    // MARK: Playing

    @Test func playsLegalMovesAndRefusesTheOthers() throws {
        var game = Game()
        let played = game.play(try #require(Move(uci: "e2e4")))
        let first = try #require(played)
        #expect(first.san == "e4")
        #expect(first.ply == 1)
        #expect(first.side == .white)
        #expect(game.position.turn == .black)

        // Not Black's piece, not a move of that piece, a king left in check.
        let notBlacks = game.play(try #require(Move(uci: "d2d4")))
        let notAMove = game.play(try #require(Move(uci: "e7e4")))
        #expect(notBlacks == nil)
        #expect(notAMove == nil)
        #expect(game.moves.count == 1)

        let pinned = try self.game("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7")
        #expect(pinned.boardEnding == .checkmate(winner: .white))
        var over = pinned
        let afterMate = over.play(try #require(Move(uci: "e8f7")))
        #expect(afterMate == nil)
    }

    @Test func castlingWrittenAsKingTakesRookIsTheSameMove() throws {
        var game = try game("e2e4 e7e5 g1f3 b8c6 f1c4 f8c5")
        let played = game.play(try #require(Move(uci: "e1h1")))
        let castle = try #require(played)
        #expect(castle.san == "O-O")
        #expect(castle.move.uci == "e1g1")
    }

    @Test func aMoveListThatBreaksTheRulesIsRefusedWhole() {
        #expect(Game(uciMoves: ["e2e4", "e7e5", "e4e5"]) == nil)
        #expect(Game(uciMoves: ["e2e4", "zz"]) == nil)
        #expect(Game(uciMoves: [])?.moves.isEmpty == true)
    }

    @Test func takingBackRestoresThePositionAndTheCount() throws {
        var game = try game("g1f3 g8f6 f3g1 f6g8")
        #expect(game.repetitions == 2)
        let taken = game.takeBack()
        let undone = try #require(taken)
        #expect(undone.san == "Ng8")
        #expect(game.repetitions == 1)
        #expect(game.position.turn == .black)
        var empty = Game()
        let nothing = empty.takeBack()
        #expect(nothing == nil)
    }

    @Test func pliesCountFromTheStartOfTheGameNotOfThePosition() throws {
        // Black to move at move 12.
        let game = try game("g8f6 e2e4", from: "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 12")
        #expect(game.startPly == 23)
        #expect(game.moves.map(\.ply) == [24, 25])
        #expect(game.moves.map(\.moveNumber) == [12, 13])
        #expect(game.moves.map(\.side) == [.black, .white])
    }

    // MARK: Draws

    @Test func theThirdOccurrenceOfAPositionCanBeClaimed() throws {
        let twice = try game("g1f3 g8f6 f3g1 f6g8")
        #expect(twice.repetitions == 2)
        #expect(twice.drawClaim == nil)
        #expect(twice.ending(claimingDraws: true) == nil)

        let thrice = try game("g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8")
        #expect(thrice.repetitions == 3)
        #expect(thrice.canClaimThreefoldRepetition)
        #expect(thrice.drawClaim == .threefoldRepetition)
        #expect(thrice.ending(claimingDraws: true) == .threefoldRepetition)
        // Nobody claims: the game goes on.
        #expect(thrice.ending(claimingDraws: false) == nil)
        #expect(thrice.boardEnding == nil)
    }

    @Test func repetitionsNeedNotFollowEachOther() throws {
        // The position after 1.Nf3 Nf6 comes back twice, with other moves in between.
        let game = try game("g1f3 g8f6 b1c3 b8c6 c3b1 c6b8 f3g1 f6g8 g1f3 g8f6")
        #expect(game.repetitions == 3)
        #expect(game.drawClaim == .threefoldRepetition)
    }

    @Test func aPositionWithOtherCastlingRightsIsAnotherPosition() throws {
        // The rooks step out and back: same pieces, but castling is gone.
        let game = try game("g1f3 g8f6 h1g1 h8g8 g1h1 g8h8 h1g1 h8g8 g1h1 g8h8")
        #expect(game.repetitions == 2)
        #expect(game.drawClaim == nil)
    }

    @Test func anEnPassantChanceMakesAnotherPosition() throws {
        // After 1.e4 a6 2.e5 d5 White may take en passant; the same pieces
        // two moves later, without that chance, are a different position.
        let game = try game("e2e4 a7a6 e4e5 d7d5 g1f3 g8h6 f3g1 h6g8")
        #expect(game.moves[3].position.enPassant != nil)
        #expect(game.repetitions == 1)
    }

    @Test func fiftyMovesWithoutACaptureOrAPawnMoveCanBeClaimed() throws {
        let almost = "8/8/8/8/8/5k2/8/R4K2 w - - 99 80"
        let quiet = try game("a1a2", from: almost)
        #expect(quiet.position.halfmoveClock == 100)
        #expect(quiet.canClaimFiftyMoves)
        #expect(quiet.drawClaim == .fiftyMoveRule)
        #expect(quiet.ending(claimingDraws: true) == .fiftyMoveRule)
        #expect(quiet.ending(claimingDraws: false) == nil)

        // A pawn move starts the count again.
        let pawn = try game("a2a3", from: "8/8/8/8/8/5k2/P7/R4K2 w - - 99 80")
        #expect(pawn.position.halfmoveClock == 0)
        #expect(pawn.drawClaim == nil)
        // So does a capture.
        let capture = try game("a1a8", from: "r7/8/8/8/8/5k2/8/R4K2 w - - 99 80")
        #expect(capture.position.halfmoveClock == 0)
    }

    @Test func mateComesBeforeAnyDrawClaim() throws {
        // Mate on the move that completes fifty: the mate stands.
        let game = try game("a1a8", from: "6k1/5ppp/8/8/8/8/5PPP/R5K1 w - - 99 80")
        #expect(game.ending(claimingDraws: true) == .checkmate(winner: .white))
    }

    @Test func boardEndings() throws {
        #expect(try game("f2f3 e7e5 g2g4 d8h4").boardEnding == .checkmate(winner: .black))
        #expect(try game("", from: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1").boardEnding == .stalemate)
        #expect(try game("", from: "8/8/8/8/8/5k2/8/5KB1 w - - 0 1").boardEnding == .insufficientMaterial)
        #expect(Game().boardEnding == nil)
        #expect(GameEnding.stalemate.isDraw)
        #expect(GameEnding.threefoldRepetition.winner == nil)
        #expect(GameEnding.checkmate(winner: .black).winner == .black)
        #expect(!GameEnding.checkmate(winner: .black).isDraw)
    }

    /// The cases of chessops (`isInsufficientMaterial`), which the site uses.
    @Test(arguments: [
        ("8/8/8/8/8/5k2/8/5K2 w - - 0 1", true),          // bare kings
        ("8/8/8/8/8/5k2/8/5KN1 w - - 0 1", true),         // a lone knight
        ("8/8/8/8/8/5k2/8/5KB1 w - - 0 1", true),         // a lone bishop
        ("8/8/8/8/8/5k2/2b5/5KB1 w - - 0 1", false),      // bishops on opposite colours
        ("8/8/8/8/8/5k2/3b4/5KB1 w - - 0 1", true),       // bishops on the same colour
        ("8/8/8/8/8/5k2/8/3B1KB1 w - - 0 1", false),      // two bishops of one side, opposite colours
        ("8/8/8/8/8/5k2/8/4BKB1 w - - 0 1", true),        // two bishops of one side, same colour
        ("8/8/8/8/8/5k2/3n4/5KN1 w - - 0 1", false),      // knight against knight: a helpmate exists
        ("8/8/8/8/8/5k2/8/4NKN1 w - - 0 1", false),       // two knights
        ("8/8/8/8/8/5k2/3n4/5KB1 w - - 0 1", false),      // bishop against knight
        ("8/8/8/8/8/5k2/4P3/5K2 w - - 0 1", false),       // a pawn
        ("8/8/8/8/8/5k2/8/R4K2 w - - 0 1", false),        // a rook
    ])
    func insufficientMaterial(fen: String, expected: Bool) throws {
        #expect(try #require(Position(fen: fen)).hasInsufficientMaterial == expected)
    }

    // MARK: Setups

    @Test(arguments: [
        (Position.startFEN, true),
        ("4k3/8/8/8/8/8/4P3/4K3 b - - 0 1", true),
        ("4k3/8/8/8/8/8/8/4KK2 w - - 0 1", false),            // two white kings
        ("4k2P/8/8/8/8/8/8/4K3 w - - 0 1", false),            // a pawn on the last rank
        ("4k3/8/8/8/8/8/8/p3K3 w - - 0 1", false),            // a pawn on the first rank
        ("4k3/8/8/8/8/8/8/4K2r b - - 0 1", false),            // White is in check and Black is to move
        ("4k3/8/8/8/8/8/8/4K2r w - - 0 1", true),             // the same check, White to answer it
        ("4k3/8/8/8/8/3n4/4q3/r3K2r w - - 0 1", false),       // more than two pieces give check
    ])
    func playableSetups(fen: String, expected: Bool) throws {
        #expect(try #require(Position(fen: fen)).isPlayableSetup == expected)
    }

    @Test func attackersAreListedBySquare() throws {
        let position = try #require(Position(fen: "4k3/8/8/8/8/3n4/4q3/r3K2r w - - 0 1"))
        let king = try #require(position.kingSquare(of: .white))
        #expect(Set(position.attackers(of: king, by: .black).map(\.description)) == ["a1", "h1", "e2", "d3"])
        #expect(Position.start.attackers(of: try #require(Square("e4")), by: .white).isEmpty)
        #expect(Position.start.attackers(of: try #require(Square("f3")), by: .white).map(\.description).sorted() == ["e2", "g1", "g2"])
    }

    // MARK: PGN

    @Test func writesAGameTheWayTheSiteDoes() throws {
        let game = try game("e2e4 e7e5 d1h5 b8c6 f1c4 g8f6 h5f7")
        let pgn = game.pgn(tags: ["White": "You", "Black": "Étienne", "Result": "1-0", "Event": "Bot game"])
        #expect(pgn == """
        [Event "Bot game"]
        [Site "?"]
        [Date "????.??.??"]
        [Round "?"]
        [White "You"]
        [Black "Étienne"]
        [Result "1-0"]

        1. e4 e5 2. Qh5 Nc6 3. Bc4 Nf6 4. Qxf7# 1-0

        """)
    }

    @Test func aGameFromAPositionCarriesItsFENAndItsMoveNumbers() throws {
        let fen = "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 12"
        let pgn = try game("g8f6 c2c4 e7e6", from: fen).pgn(tags: ["Note": "say \"hi\""])
        #expect(pgn.contains("[FEN \"\(fen)\"]\n[SetUp \"1\"]"))
        #expect(pgn.contains("[Note \"say \\\"hi\\\"\"]"))
        #expect(pgn.hasSuffix("\n\n12... Nf6 13. c4 e6 *\n"))
        #expect(Game().pgn().hasSuffix("[Result \"*\"]\n\n*\n"))
    }
}
