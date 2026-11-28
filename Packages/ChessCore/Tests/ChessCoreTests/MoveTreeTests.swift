import Testing
@testable import ChessCore

@Suite struct MoveTreeTests {
    private func line(_ tree: MoveTree, _ ids: [MoveTree.NodeID]) -> [String] {
        ids.map { tree[$0].san }
    }

    @Test func addsMovesAndReusesAnExistingChild() throws {
        var tree = MoveTree()
        let e4 = try tree.must("e4", after: tree.root)
        let e5 = try tree.must("e5", after: e4)
        #expect(tree.add(san: "e5", after: e4) == e5)
        #expect(tree[e4].children == [e5])
        #expect(tree[e5].moveNumberText == "1...")
        #expect(tree[e5].side == .black)
        #expect(tree.add(san: "Ke3", after: e5) == nil)
        #expect(tree.mainLineSAN == ["e4", "e5"])
    }

    @Test func branchesAndNavigates() throws {
        var tree = MoveTree()
        let e4 = try tree.must("e4", after: tree.root)
        let e5 = try tree.must("e5", after: e4)
        let nf3 = try tree.must("Nf3", after: e5)
        let c5 = try tree.must("c5", after: e4)
        let nc3 = try tree.must("Nc3", after: c5)

        #expect(tree[e4].children == [e5, c5])
        #expect(tree.path(to: nc3) == [e4, c5, nc3])
        #expect(tree.isOnMainLine(nf3))
        #expect(!tree.isOnMainLine(nc3))
        #expect(tree.end(of: e4) == nf3)
        #expect(tree.end(of: c5) == nc3)
        #expect(tree[nc3].parent == c5)
        #expect(tree.hasVariations)
        #expect(line(tree, tree.mainLine) == ["e4", "e5", "Nf3"])
    }

    @Test func promotesAVariationOneLevelThenToTheMainLine() throws {
        var tree = MoveTree()
        let e4 = try tree.must("e4", after: tree.root)
        let e5 = try tree.must("e5", after: e4)
        let nf3 = try tree.must("Nf3", after: e5)
        let nc6 = try tree.must("Nc6", after: nf3)
        let d6 = try tree.must("d6", after: nf3)
        // A variation inside the variation.
        let d4 = try tree.must("d4", after: d6)
        let bc4 = try tree.must("Bc4", after: d6)
        _ = nc6
        _ = d4

        tree.promote(bc4)
        #expect(tree[d6].children.first == bc4)
        #expect(!tree.isOnMainLine(bc4))

        tree.makeMainLine(bc4)
        #expect(tree.isOnMainLine(bc4))
        #expect(tree.mainLineSAN == ["e4", "e5", "Nf3", "d6", "Bc4"])

        // Promoting a main line move changes nothing.
        let before = tree
        tree.promote(e5)
        #expect(tree == before)
    }

    @Test func deletesAMoveAndEverythingAfterIt() throws {
        var tree = MoveTree()
        let e4 = try tree.must("e4", after: tree.root)
        let e5 = try tree.must("e5", after: e4)
        let nf3 = try tree.must("Nf3", after: e5)
        let c5 = try tree.must("c5", after: e4)

        #expect(tree.delete(e5) == e4)
        #expect(!tree.contains(e5))
        #expect(!tree.contains(nf3))
        #expect(tree[e4].children == [c5])
        #expect(tree.mainLineSAN == ["e4", "c5"])
        #expect(tree.delete(tree.root) == nil)
    }

    @Test func startsFromAPositionWithBlackToMove() throws {
        let start = try #require(Position(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"))
        var tree = MoveTree(start: start)
        let c5 = try tree.must("c5", after: tree.root)
        let nf3 = try tree.must("Nf3", after: c5)
        #expect(tree[c5].moveNumberText == "1...")
        #expect(tree[nf3].moveNumberText == "2.")
        #expect(tree.movetext == "1... c5 2. Nf3")
    }
}

@Suite struct PGNTests {
    @Test func writesVariationsWithTheirMoveNumbers() throws {
        var tree = MoveTree()
        let e4 = try tree.must("e4", after: tree.root)
        let e5 = try tree.must("e5", after: e4)
        let nf3 = try tree.must("Nf3", after: e5)
        let c5 = try tree.must("c5", after: e4)
        _ = try tree.must("Nf3", after: c5)
        let nc6 = try tree.must("Nc6", after: nf3)
        tree.setComment("The most common reply.", on: nc6)
        _ = try tree.must("Bb5", after: nc6)

        #expect(tree.movetext == "1. e4 e5 (1... c5 2. Nf3) 2. Nf3 Nc6 {The most common reply.} 3. Bb5")
    }

    @Test func readsTagsCommentsNestedVariationsAndGlyphs() throws {
        let text = """
        [Event "Club night"]
        [White "Ana"]
        [Black "Ben"]
        [Result "1-0"]

        1. e4 e5 {Open game} (1... c5 2. Nf3 (2. Nc3 Nc6) 2... d6) 2. Nf3!? Nc6 $1
        3.Bb5 a6 ; the Morphy defence
        4. Ba4 1-0
        """
        let tree = try MoveTree(pgn: text)
        #expect(tree.headers.first { $0.name == "White" }?.value == "Ana")
        #expect(tree.mainLineSAN == ["e4", "e5", "Nf3", "Nc6", "Bb5", "a6", "Ba4"])
        let e4 = tree.mainLine[0]
        let e5 = tree.mainLine[1]
        #expect(tree[e5].comment == "Open game")
        #expect(tree[e4].children.count == 2)
        let c5 = tree[e4].children[1]
        #expect(tree[c5].san == "c5")
        let nf3 = try #require(tree[c5].children.first)
        #expect(tree[nf3].children.map { tree[$0].san } == ["d6"])
        // "(2. Nc3 Nc6)" is an alternative to 2. Nf3 inside the Sicilian.
        #expect(tree[c5].children.map { tree[$0].san } == ["Nf3", "Nc3"])
    }

    @Test func roundTripsThroughText() throws {
        let text = "1. e4 e5 (1... c5 2. Nf3 (2. Nc3 Nc6) 2... d6) 2. Nf3 Nc6 {A note} 3. Bb5 *"
        let tree = try MoveTree(pgn: text)
        #expect(tree.movetext == "1. e4 e5 (1... c5 2. Nf3 (2. Nc3 Nc6) 2... d6) 2. Nf3 Nc6 {A note} 3. Bb5")
        let again = try MoveTree(pgn: tree.pgn())
        #expect(again.movetext == tree.movetext)
        #expect(again.mainLineSAN == tree.mainLineSAN)
    }

    @Test func writesTheStartingPositionAndResult() throws {
        let start = try #require(Position(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"))
        var tree = MoveTree(start: start)
        _ = try tree.must("Re8#", after: tree.root)
        let pgn = tree.pgn(result: "1-0")
        #expect(pgn.contains("[SetUp \"1\"]"))
        #expect(pgn.contains("[FEN \"6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1\"]"))
        #expect(pgn.contains("[Result \"1-0\"]"))
        #expect(pgn.hasSuffix("1. Re8# 1-0\n"))

        let back = try MoveTree(pgn: pgn)
        #expect(back.start == start)
        #expect(back.mainLineSAN == ["Re8#"])
    }

    @Test func wrapsLongGamesAt80Columns() throws {
        var tree = MoveTree()
        var at = tree.root
        for san in ["Nf3", "Nf6", "Ng1", "Ng8"] + Array(repeating: ["Nf3", "Nf6", "Ng1", "Ng8"], count: 10).flatMap({ $0 }) {
            at = try tree.must(san, after: at)
        }
        let lines = tree.pgn().split(separator: "\n").filter { !$0.hasPrefix("[") }
        #expect(lines.count > 1)
        #expect(lines.allSatisfy { $0.count <= 80 })
    }

    @Test func reportsTheFirstIllegalMove() {
        #expect(throws: PGNError.illegalMove("2... Bh6")) {
            try MoveTree(pgn: "[Event \"Broken\"]\n\n1. e4 c5 2. Nf3 Bh6 *")
        }
        #expect(throws: PGNError.illegalMove("1. e5")) { try MoveTree(pgn: "1. e5") }
        #expect(throws: PGNError.badVariation) { try MoveTree(pgn: "1. e4 (1. d4") }
        #expect(throws: PGNError.badVariation) { try MoveTree(pgn: "(1. d4) 1. e4") }
        #expect(throws: PGNError.badFEN("nonsense")) { try MoveTree(pgn: "[FEN \"nonsense\"]\n\n*") }
    }

    @Test func readsOnlyTheFirstGameAndBareMoves() throws {
        let two = try MoveTree(pgn: "[Event \"A\"]\n\n1. d4 d5 1/2-1/2\n\n[Event \"B\"]\n\n1. e4 *")
        #expect(two.mainLineSAN == ["d4", "d5"])
        let bare = try MoveTree(pgn: "e4 e5 Nf3 Nc6 0-0")
        #expect(bare.mainLineSAN == ["e4", "e5", "Nf3", "Nc6"])
    }
}

@Suite struct SetupTests {
    @Test func findsImpossiblePositions() throws {
        #expect(Position.start.setupProblem == nil)
        #expect(try #require(Position(fen: "4k3/8/8/8/8/8/8/4KK2 w - - 0 1")).setupProblem == .kings)
        #expect(try #require(Position(fen: "4k2P/8/8/8/8/8/8/4K3 w - - 0 1")).setupProblem == .pawnOnBackRank)
        // White to move while Black's king is attacked by the rook.
        #expect(try #require(Position(fen: "4k3/8/8/8/8/8/8/R3K2r w - - 0 1")).setupProblem == nil)
        #expect(try #require(Position(fen: "4k3/8/8/8/8/8/8/4R1K1 w - - 0 1")).setupProblem == .sideNotToMoveInCheck)
    }

    @Test func turnsAnEngineLineIntoSAN() {
        #expect(Position.start.sanLine(uci: ["e2e4", "e7e5", "g1f3"]) == ["e4", "e5", "Nf3"])
        #expect(Position.start.sanLine(uci: ["e2e4", "e2e4"]) == ["e4"])
        #expect(Position.start.sanLine(uci: []) == [])
    }
}

private struct MissingMove: Error {}

extension MoveTree {
    /// Plays a SAN move or fails the test.
    mutating func must(_ san: String, after parent: NodeID) throws -> NodeID {
        guard let id = add(san: san, after: parent) else { throw MissingMove() }
        return id
    }
}
