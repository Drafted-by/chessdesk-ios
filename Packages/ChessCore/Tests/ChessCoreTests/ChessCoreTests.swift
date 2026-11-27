import Testing
@testable import ChessCore

private func perft(_ position: Position, _ depth: Int) -> Int {
    if depth == 0 { return 1 }
    let moves = position.legalMoves()
    if depth == 1 { return moves.count }
    return moves.reduce(0) { $0 + perft(position.playing($1).unsafelyUnwrapped, depth - 1) }
}

/// Node counts from the Chess Programming Wiki "Perft Results" page. They
/// cover castling, en passant, promotion, pins and discovered checks.
@Suite struct PerftTests {
    @Test(arguments: [
        (Position.startFEN, 4, 197_281),
        ("r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1", 3, 97_862),
        ("8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", 4, 43_238),
        ("r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1", 3, 9_467),
        ("rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8", 3, 62_379),
        ("r4rk1/1pp1qppp/p1np1n2/2b1p1B1/2B1P1b1/P1NP1N2/1PP1QPPP/R4RK1 w - - 0 10", 3, 89_890),
    ])
    func nodeCounts(fen: String, depth: Int, expected: Int) throws {
        let position = try #require(Position(fen: fen))
        #expect(perft(position, depth) == expected)
    }
}

@Suite struct FENTests {
    @Test func roundTrips() throws {
        let fens = [
            Position.startFEN,
            "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
            "rnbqkbnr/ppp1pppp/8/8/3pP3/2N5/PPPP1PPP/R1BQKBNR b KQkq e3 0 3",
            "8/8/8/8/8/5k2/8/5K2 b - - 12 60",
        ]
        for fen in fens {
            #expect(try #require(Position(fen: fen)).fen == fen)
        }
    }

    /// The en passant square is written only when the capture can be played.
    @Test func enPassantSquareOnlyWhenCapturable() throws {
        let noCapture = try #require(Position(fen: "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq c6 0 2"))
        #expect(noCapture.enPassant == Square("c6"))
        #expect(noCapture.fen == "rnbqkbnr/pp1ppppp/8/2p5/4P3/8/PPPP1PPP/RNBQKBNR w KQkq - 0 2")
        // The capturing pawn is pinned to its king: not capturable either.
        let pinned = try #require(Position(fen: "8/8/8/8/k2Pp2R/8/8/4K3 b - d3 0 1"))
        #expect(pinned.capturableEnPassant == nil)
    }

    @Test func rejectsMalformed() {
        #expect(Position(fen: "") == nil)
        #expect(Position(fen: "8/8/8/8/8/8/8/8 w - - 0 1") == nil)
        #expect(Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBN w KQkq - 0 1") == nil)
        #expect(Position(fen: "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR x KQkq - 0 1") == nil)
    }

    @Test func dropsCastlingRightsWithoutRook() throws {
        let position = try #require(Position(fen: "4k3/8/8/8/8/8/8/4K2R w KQkq - 0 1"))
        #expect(position.castling == [.whiteKingside])
    }

    @Test func positionKeyIgnoresCounters() throws {
        let one = try #require(Position(fen: "8/8/8/8/8/5k2/8/5K2 b - - 12 60"))
        let two = try #require(Position(fen: "8/8/8/8/8/5k2/8/5K2 b - - 0 1"))
        #expect(one.positionKey == two.positionKey)
    }
}

@Suite struct MoveTests {
    private func play(_ sans: [String], from start: Position = .start) throws -> Position {
        var position = start
        for san in sans {
            let move = try #require(position.move(san: san), "no move for \(san)")
            position = try #require(position.playing(move))
        }
        return position
    }

    @Test func uciParsing() {
        #expect(Move(uci: "e2e4")?.uci == "e2e4")
        #expect(Move(uci: "e7e8q")?.promotion == .queen)
        #expect(Move(uci: "e7e8k") == nil)
        #expect(Move(uci: "e2") == nil)
        #expect(Move(uci: "i2e4") == nil)
    }

    @Test func playsAnOpeningAndWritesFEN() throws {
        let position = try play(["e4", "c5", "Nf3", "d6", "d4", "cxd4", "Nxd4", "Nf6", "Nc3", "a6"])
        #expect(position.fen == "rnbqkb1r/1p2pppp/p2p1n2/8/3NP3/2N5/PPP2PPP/R1BQKB1R w KQkq - 0 6")
    }

    @Test func castlingMovesTheRookAndAcceptsKingTakesRook() throws {
        let before = try play(["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5"])
        let short = try #require(Move(uci: "e1g1"))
        #expect(before.san(for: short) == "O-O")
        let viaRook = try #require(Move(uci: "e1h1"))
        #expect(before.normalized(viaRook) == short)
        let after = try #require(before.playing(viaRook))
        #expect(after[try #require(Square("f1"))] == Piece(.white, .rook))
        #expect(after[try #require(Square("g1"))] == Piece(.white, .king))
        #expect(!after.castling.contains(.whiteKingside))
        #expect(before.move(san: "0-0") == short)
    }

    @Test func enPassantRemovesThePawn() throws {
        let before = try play(["e4", "a6", "e5", "d5"])
        let move = try #require(before.move(san: "exd6"))
        #expect(before.isEnPassant(move))
        let after = try #require(before.playing(move))
        #expect(after[try #require(Square("d5"))] == nil)
    }

    @Test func promotionAndMate() throws {
        let position = try #require(Position(fen: "8/6P1/8/8/8/k7/8/K7 w - - 0 1"))
        let queen = try #require(Move(uci: "g7g8q"))
        #expect(position.san(for: queen) == "g8=Q")
        #expect(position.legalMoves(from: queen.from).count == 4)

        let mate = try play(["f3", "e5", "g4", "Qh4#"])
        #expect(mate.isCheckmate)
        #expect(mate.outcome == .checkmate(winner: .black))
    }

    @Test func sanDisambiguation() throws {
        let rooks = try #require(Position(fen: "4k3/8/8/8/R6R/8/8/4K3 w - - 0 1"))
        #expect(rooks.san(for: try #require(Move(uci: "a4d4"))) == "Rad4")
        let files = try #require(Position(fen: "4k3/8/R7/8/8/8/R7/4K3 w - - 0 1"))
        #expect(files.san(for: try #require(Move(uci: "a2a4"))) == "R2a4")
        let queens = try #require(Position(fen: "4k3/8/8/8/Q5Q1/8/8/Q3K3 w - - 0 1"))
        #expect(queens.san(for: try #require(Move(uci: "a4d1"))) == "Qa4d1")
    }

    @Test func illegalMovesAreRefused() throws {
        let pinned = try #require(Position(fen: "4k3/4r3/8/8/8/8/4B3/4K3 w - - 0 1"))
        #expect(pinned.playing(try #require(Move(uci: "e2d3"))) == nil)
        #expect(Position.start.playing(try #require(Move(uci: "e2e5"))) == nil)
        #expect(Position.start.playing(try #require(Move(uci: "e7e5"))) == nil)
    }

    @Test func drawnOutcomes() throws {
        #expect(try #require(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")).outcome == .stalemate)
        #expect(try #require(Position(fen: "8/8/8/8/8/5k2/8/5KB1 w - - 0 1")).outcome == .insufficientMaterial)
        #expect(try #require(Position(fen: "8/8/8/8/8/5k2/8/R4K2 w - - 100 80")).outcome == .fiftyMoveRule)
    }
}
