import ChessCore
import Foundation
import StockfishEngine
import Testing
@testable import ChessDesk

// MARK: Stub engine

/// A live engine the test drives: it records each search, and the test
/// sends its lines when it wants.
nonisolated final class StubLiveEngine: LiveAnalysing, @unchecked Sendable {
    struct Search {
        let fen: String
        let continuation: AsyncThrowingStream<LiveSearchUpdate, Error>.Continuation
    }

    private let lock = NSLock()
    private var _searches: [Search] = []
    private var _ended: [String] = []

    var searches: [Search] { lock.withLock { _searches } }
    var ended: [String] { lock.withLock { _ended } }

    func analyse(fen: String, lines: Int) -> AsyncThrowingStream<LiveSearchUpdate, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                self?.lock.withLock { self?._ended.append(fen) }
            }
            lock.withLock { _searches.append(Search(fen: fen, continuation: continuation)) }
        }
    }
}

private func evaluation(_ cp: Int?, mate: Int? = nil, depth: Int = 12, _ pv: [String]) -> EngineEvaluation {
    EngineEvaluation(centipawns: cp, mate: mate, depth: depth, principalVariation: pv)
}

// MARK: Analysis board

@MainActor
@Suite struct AnalysisBoardTests {
    private func board(_ engine: StubLiveEngine = StubLiveEngine()) -> AnalysisBoardModel {
        let model = AnalysisBoardModel(engine: LiveAnalysisModel(engine: engine))
        model.start()
        return model
    }

    @Test func searchesOnlyOnceStartedAndLetsGoWhenStopped() async throws {
        let engine = StubLiveEngine()
        let model = AnalysisBoardModel(engine: LiveAnalysisModel(engine: engine))
        // SwiftUI makes models it throws away: they must not search.
        #expect(model.play(try #require(model.position.move(san: "e4"))))
        #expect(engine.searches.isEmpty)
        model.start()
        #expect(engine.searches.map(\.fen) == [model.fen])
        model.stop()
        await settled { engine.ended.count == 1 }
        #expect(engine.ended == [model.fen])
        model.back()
        #expect(engine.searches.count == 1)
    }

    private func play(_ model: AnalysisBoardModel, _ sans: String...) throws {
        for san in sans {
            let move = try #require(model.position.move(san: san), "\(san) is not legal")
            #expect(model.play(move))
        }
    }

    @Test func playsBothSidesAndBranchesIntoAVariation() throws {
        let model = board()
        try play(model, "e4", "e5", "Nf3")
        model.back()
        model.back()
        try play(model, "c5")
        #expect(model.tree.mainLineSAN == ["e4", "e5", "Nf3"])
        #expect(!model.isOnMainLine)
        #expect(model.tree.movetext == "1. e4 e5 (1... c5) 2. Nf3")
        // Playing a move that exists follows it instead of adding it again.
        model.toStart()
        try play(model, "e4", "e5")
        #expect(model.isOnMainLine)
        #expect(model.tree.nodes.count == 5)
    }

    @Test func walksTheTree() throws {
        let model = board()
        try play(model, "d4", "d5", "c4")
        model.toStart()
        #expect(!model.canGoBack)
        model.forward()
        #expect(model.node.san == "d4")
        model.toEnd()
        #expect(model.node.san == "c4")
        #expect(!model.canGoForward)
        model.flip()
        #expect(model.orientation == .black)
    }

    @Test func promotesAndDeletesFromTheBoard() throws {
        let model = board()
        try play(model, "e4", "e5", "Nf3")
        model.go(to: model.tree.mainLine[0])
        try play(model, "c5", "Nf3")
        let sicilian = model.cursor
        model.makeMainLine(sicilian)
        #expect(model.tree.mainLineSAN == ["e4", "c5", "Nf3"])
        #expect(model.isOnMainLine)

        // Deleting the line under the cursor sends it back to the branch point.
        let c5 = model.tree.mainLine[1]
        model.delete(c5)
        #expect(model.cursor == model.tree.mainLine[0])
        #expect(model.tree.mainLineSAN == ["e4", "e5", "Nf3"])
        // Deleting elsewhere leaves the cursor alone.
        let here = model.cursor
        model.delete(model.tree.mainLine[2])
        #expect(model.cursor == here)
        #expect(model.tree.mainLineSAN == ["e4", "e5"])
    }

    @Test func pgnGoesOutAndComesBackIn() throws {
        let model = board()
        try play(model, "e4", "e5", "Nf3", "Nc6")
        model.go(to: model.tree.mainLine[1])
        try play(model, "Bc4")
        let pgn = model.pgn
        #expect(pgn.contains("1. e4 e5 2. Nf3 (2. Bc4) 2... Nc6 *"))

        let loaded = try AnalysisInput.read(pgn).get()
        let other = board()
        other.load(loaded)
        #expect(other.tree.movetext == model.tree.movetext)
        #expect(other.cursor == other.tree.root)
    }

    @Test func playsAnEngineLine() async throws {
        let engine = StubLiveEngine()
        let model = board(engine)
        await settled { engine.searches.count == 1 }
        engine.searches[0].continuation.yield(LiveSearchUpdate(depth: 12, lines: [
            evaluation(30, ["e2e4", "e7e5", "g1f3"]),
        ]))
        await settled { !model.engine.lines.isEmpty }
        let line = try #require(model.engine.best)
        model.play(line, count: 1)
        #expect(model.node.san == "e4")
        model.back()
        model.play(line)
        #expect(model.tree.path(to: model.cursor).map { model.tree[$0].san } == ["e4", "e5", "Nf3"])
    }

    @Test func aGameOpensAtItsMove() throws {
        let line = GameLine(pgn: "[White \"Ana\"]\n[Black \"Ben\"]\n[Result \"1-0\"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 1-0")
        let (tree, cursor) = AnalysisBoardModel.tree(from: line, ply: 3)
        #expect(tree.mainLineSAN == ["e4", "e5", "Nf3", "Nc6", "Bb5"])
        #expect(tree[cursor].san == "Nf3")
        #expect(tree.headers.map(\.name) == ["White", "Black", "Result"])
        #expect(tree.pgn().contains("[White \"Ana\"]"))
        #expect(tree.pgn().hasSuffix("3. Bb5 1-0\n"))
        #expect(AnalysisBoardModel.tree(from: line, ply: 0).1 == tree.root)
    }

    @Test func namesTheGameOver() throws {
        let model = board()
        try play(model, "f3", "e5", "g4", "Qh4#")
        #expect(model.outcomeText == "Checkmate. Black wins.")
        model.reset(to: try #require(Position(fen: "7k/5Q2/6K1/8/8/8/8/8 b - - 0 1")))
        #expect(model.outcomeText == "Stalemate. Draw.")
    }
}

// MARK: Live analysis

@MainActor
@Suite struct LiveAnalysisTests {
    @Test func aNewPositionEndsTheSearchBeforeTheNextStarts() async throws {
        let engine = StubLiveEngine()
        let model = LiveAnalysisModel(engine: engine)
        model.show(.start)
        await settled { engine.searches.count == 1 }
        let e4 = try #require(Move(uci: "e2e4"))
        let after = try #require(Position.start.playing(e4))
        model.show(after)
        await settled { engine.ended.count == 1 }
        #expect(engine.ended == [Position.start.fen])
        #expect(engine.searches.map(\.fen) == [Position.start.fen, after.fen])

        // A late report of the old position is not shown.
        engine.searches[0].continuation.yield(LiveSearchUpdate(depth: 20, lines: [evaluation(40, ["d2d4"])]))
        engine.searches[1].continuation.yield(LiveSearchUpdate(depth: 9, lines: [evaluation(-30, ["c7c5"])]))
        await settled { !model.lines.isEmpty }
        #expect(model.depth == 9)
        #expect(model.lines.map(\.san) == [["c5"]])
        #expect(model.position == after)
    }

    @Test func linesArriveBestFirstFromWhitesPointOfView() async throws {
        let engine = StubLiveEngine()
        let model = LiveAnalysisModel(engine: engine)
        // Black to move: the engine's scores are Black's.
        let position = try #require(Position(fen: "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"))
        model.show(position)
        await settled { engine.searches.count == 1 }
        let search = engine.searches[0]
        search.continuation.yield(LiveSearchUpdate(depth: 10, lines: [
            evaluation(-25, ["c7c5", "g1f3"]),
            evaluation(-31, ["e7e5"]),
            evaluation(nil, mate: -3, ["f7f6"]),
        ]))
        await settled { model.lines.count == 3 }
        #expect(model.lines.map(\.id) == [1, 2, 3])
        #expect(model.lines.map(\.scoreText) == ["+0.25", "+0.31", "#3"])
        #expect(model.lines[0].san == ["c5", "Nf3"])
        #expect(model.status == .searching)

        search.continuation.yield(LiveSearchUpdate(depth: 11, lines: [evaluation(-20, ["e7e5"])]))
        await settled { model.depth == 11 }
        #expect(model.lines.map(\.san) == [["e5"]])
        search.continuation.finish()
        await settled { model.status == .done }
        #expect(model.status == .done)
    }

    @Test func offFinishedAndStoppedSearchNothing() async throws {
        let engine = StubLiveEngine()
        let model = LiveAnalysisModel(engine: engine)
        model.isOn = false
        model.show(.start)
        #expect(model.status == .off)
        model.isOn = true
        await settled { engine.searches.count == 1 }
        model.stop()
        await settled { engine.ended.count == 1 }
        #expect(engine.ended.count == 1)
        model.resume()
        await settled { engine.searches.count == 2 }
        #expect(engine.searches.count == 2)

        let mated = try #require(Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"))
        model.show(mated)
        #expect(model.status == .done)
        #expect(engine.searches.count == 2)
    }

    @Test func scoresAndTheBarFollowTheSite() {
        #expect(EngineScore.text(whiteCentipawns: 31, whiteMate: nil) == "+0.31")
        #expect(EngineScore.text(whiteCentipawns: -120, whiteMate: nil) == "-1.20")
        #expect(EngineScore.text(whiteCentipawns: 0, whiteMate: nil) == "0.00")
        #expect(EngineScore.text(whiteCentipawns: nil, whiteMate: -2) == "#-2")
        // eval-bar.test.tsx
        #expect(EngineScore.whiteShare(whiteCentipawns: nil, whiteMate: nil) == 50)
        #expect(EngineScore.whiteShare(whiteCentipawns: 100, whiteMate: nil) == 57)
        #expect(EngineScore.whiteShare(whiteCentipawns: -100, whiteMate: nil) == 43)
        #expect(EngineScore.whiteShare(whiteCentipawns: 20000, whiteMate: nil) == 97)
        #expect(EngineScore.whiteShare(whiteCentipawns: -20000, whiteMate: nil) == 3)
        #expect(EngineScore.whiteShare(whiteCentipawns: nil, whiteMate: 3) == 100)
        #expect(EngineScore.whiteShare(whiteCentipawns: nil, whiteMate: -2) == 0)
        #expect(EngineScore.tone(whiteCentipawns: 0, whiteMate: nil) == .even)
        #expect(EngineScore.tone(whiteCentipawns: nil, whiteMate: -1) == .black)
    }
}

// MARK: Pasting a position

@Suite struct AnalysisInputTests {
    /// The site's `composeFen` tests (`lib/next-move/position.test.ts`).
    @Test func composesAFENWithTheSideToMove() {
        #expect(AnalysisInput.composeFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR", sideToMove: "b")
            == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b - - 0 1")
        #expect(AnalysisInput.composeFEN("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", sideToMove: "b")
            == "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1")
        #expect(AnalysisInput.composeFEN("not/a/fen", sideToMove: "w") == nil)
        for castling in ["\u{041A}Qkq", "KQkq-", "KQBk", "KQkx", "0"] {
            #expect(AnalysisInput.composeFEN("r3k2r/8/8/8/8/8/8/R3K2R w \(castling) - 0 1", sideToMove: "w")
                == "r3k2r/8/8/8/8/8/8/R3K2R w - - 0 1")
        }
        #expect(AnalysisInput.composeFEN("r3k2r/8/8/8/8/8/8/R3K2R w Kq - 0 1", sideToMove: "b") == "r3k2r/8/8/8/8/8/8/R3K2R b Kq - 0 1")
        // Shredder letters of a standard game read as KQkq.
        #expect(AnalysisInput.composeFEN("r3k2r/8/8/8/8/8/8/R3K2R w HAha - 0 1", sideToMove: nil) == "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1")
        #expect(AnalysisInput.composeFEN("4k3/8/8/8/8/8/8/4K3 w - e9 x 0", sideToMove: "w") == "4k3/8/8/8/8/8/8/4K3 w - - 0 1")
        #expect(AnalysisInput.composeFEN("4k3/8/8/8/8/8/8/4K3 b - e3 12 40", sideToMove: "b") == "4k3/8/8/8/8/8/8/4K3 b - e3 12 40")
    }

    @Test func readsAFENOrAPGNAndSaysWhatIsWrong() throws {
        let fen = try AnalysisInput.read("7k/5Q2/6K1/8/8/8/8/8 w - - 0 1").get()
        #expect(fen.tree.start.fen == "7k/5Q2/6K1/8/8/8/8/8 w - - 0 1")
        #expect(fen.orientation == .white)
        let black = try AnalysisInput.read("7k/5Q2/6K1/8/8/8/8/8", sideToMove: .black).get()
        #expect(black.tree.start.turn == .black)
        #expect(black.orientation == .black)

        let game = try AnalysisInput.read("1. e4 e5 2. Nf3 *").get()
        #expect(game.tree.mainLineSAN == ["e4", "e5", "Nf3"])
        #expect(game.orientation == nil)

        #expect(AnalysisInput.read("  ") == .failure(.empty))
        #expect(AnalysisInput.read("8/8/8/8/8/8/8/8 w - - 0 1") == .failure(.badFEN))
        #expect(AnalysisInput.read("4k3/8/8/8/8/8/8/4R1K1 w - - 0 1") == .failure(.impossible(.sideNotToMoveInCheck)))
        #expect(AnalysisInput.read("1. e4 c5 2. Nf3 Bh6") == .failure(.pgn(.illegalMove("2... Bh6"))))
    }
}

extension Result where Success == AnalysisInput.Loaded, Failure == AnalysisInput.Failure {
    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.failure(a), .failure(b)): a == b
        default: false
        }
    }
}

// MARK: Opening names

@Suite struct OpeningBookTests {
    private func book() async throws -> OpeningBook {
        try #require(await OpeningBook.bundled())
    }

    private func line(_ text: String) throws -> (sans: [String], position: Position) {
        let tree = try MoveTree(pgn: text)
        return (tree.mainLineSAN, tree[tree.mainLine.last ?? tree.root].position)
    }

    /// The site's `identify.test.ts`.
    @Test func namesTheVariationOfAMoveSequence() async throws {
        let book = try await book()
        let najdorf = try line("1. e4 c5 2. Nf3 d6 3. d4 cxd4 4. Nxd4 Nf6 5. Nc3 a6")
        let opening = try #require(book.identify(moves: najdorf.sans, position: najdorf.position))
        #expect(opening.eco == "B90")
        #expect(opening.name == "Sicilian Defense: Najdorf Variation")
    }

    @Test func findsAnOpeningReachedByAnotherMoveOrder() async throws {
        let book = try await book()
        let order = try line("1. d4 Nf6 2. c4 e6 3. Nc3 d5")
        let opening = try #require(book.identify(moves: order.sans, position: order.position))
        #expect(opening.eco == "D35")
        #expect(opening.name == "Queen's Gambit Declined: Normal Defense")
        let fen = try #require(Position(fen: "rnbqkb1r/ppp2ppp/4pn2/3p4/2PP4/2N5/PP2PPPP/R1BQKBNR w KQkq - 0 4"))
        #expect(book.identify(position: fen)?.eco == "D35")
        #expect(book.identify(position: try #require(Position(fen: "7k/8/8/8/8/8/8/K7 w - - 0 1"))) == nil)
    }

    @Test func theBoardNamesTheDeepestNamedMoveOfItsLine() async throws {
        let model = AnalysisBoardModel(engine: LiveAnalysisModel(engine: StubLiveEngine()))
        for san in ["e4", "e5", "Nf3", "Nc6", "Bc4", "Bc5", "a3"] {
            #expect(model.play(try #require(model.position.move(san: san))))
        }
        await model.loadOpenings()
        // 4. a3 has no name of its own: the Italian it comes from is shown.
        #expect(model.opening?.name.hasPrefix("Italian Game") == true)
    }
}

// MARK: Trainers and tools

@MainActor
@Suite struct CoordinateTrainerTests {
    private func defaults() -> UserDefaults {
        let name = "coordinates-\(UUID().uuidString)"
        return UserDefaults(suiteName: name).unsafelyUnwrapped
    }

    @Test func scoresRightTapsAndKeepsTheTargetOnAWrongOne() throws {
        var draws = ["e4", "e4", "d5", "a1"].compactMap { Square($0) }
        let trainer = CoordinateTrainer(defaults: defaults()) { draws.removeFirst() }
        #expect(!trainer.tap(try #require(Square("e4"))))
        trainer.start()
        #expect(trainer.target == Square("e4"))
        #expect(!trainer.tap(try #require(Square("e5"))))
        #expect(trainer.flash == .init(square: Square("e5")!, right: false))
        #expect(trainer.target == Square("e4"))
        #expect(trainer.tap(try #require(Square("e4"))))
        #expect(trainer.score == 1)
        // The next target is never the same square twice in a row.
        #expect(trainer.target == Square("d5"))
    }

    @Test func aRoundLastsThirtySecondsAndKeepsTheBest() throws {
        let store = defaults()
        var flip = false
        let trainer = CoordinateTrainer(defaults: store) {
            flip.toggle()
            return flip ? Square("h8")! : Square("a1")!
        }
        trainer.start()
        trainer.tap(try #require(Square("h8")))
        for _ in 0..<29 { trainer.tick() }
        #expect(trainer.phase == .playing)
        #expect(trainer.secondsLeft == 1)
        trainer.tick()
        #expect(trainer.phase == .over)
        #expect(trainer.best == 1)
        #expect(!trainer.tap(try #require(Square("h8"))))
        #expect(CoordinateTrainer(defaults: store).best == 1)
    }
}

/// The site's `elo-calculator.test.tsx` numbers.
@Suite struct EloTests {
    private func change(_ player: Double?, _ opponent: Double?, _ score: Double = 1, k: Double = 20) -> RatingChangeResult? {
        RatingChangeResult(player: player, opponent: opponent, score: score, k: k)
    }

    @Test func ratingChange() throws {
        let win = try #require(change(1500, 1600))
        #expect(win.expected == "0.360")
        #expect(win.delta == "+12.8")
        #expect(win.newRating == "1513")
        #expect(change(1500, 1600, 0)?.delta == "-7.2")
        #expect(change(1500, 1600, 0)?.newRating == "1493")
        #expect(change(1500, 1600, 0.5)?.delta == "+2.8")
        #expect(change(1500, 1600, 0.5)?.newRating == "1503")
        #expect(change(1500, 1500)?.expected == "0.500")
        #expect(change(1500, 1500)?.delta == "+10.0")
        #expect(change(1500, 1600, k: 40)?.delta == "+25.6")
        #expect(change(2000, 1600)?.expected == "0.909")
        #expect(change(2000, 1600)?.delta == "+1.8")
        #expect(change(nil, 1600) == nil)
        #expect(EloMath.rating("") == nil)
        #expect(EloMath.rating("abc") == nil)
    }

    @Test func fideCountsAGapOver400As400() throws {
        let capped = try #require(change(1500, 2000))
        #expect(capped.expected == "0.091")
        #expect(capped.delta == "+18.2")
        #expect(capped.newRating == "1518")
        #expect(capped.capped)
        #expect(change(1500, 1600)?.capped == false)
        #expect(EloMath.countedOpponent(player: 2700, opponent: 2000) == 2000)
    }

    @Test func performanceRating() {
        func games(_ list: [(Double, Double)]) -> [EloMath.Game] { list.map { EloMath.Game(opponent: $0.0, score: $0.1) } }
        #expect(EloMath.performance(games([(2000, 1), (2100, 0.5), (1900, 0)])) == 2000)
        #expect(EloMath.performance(games([(2000, 1), (2100, 0.5), (1900, 0), (2500, 1)])) == 2220)
        #expect(EloMath.performance(games([(2100, 0.5), (1900, 0)])) == 1807)
        #expect(EloMath.performance(games([(2000, 1), (2100, 1), (1900, 1)])) == 2800)
        #expect(EloMath.performance([]) == nil)
        #expect(EloMath.dpTable.count == 101)
        #expect(EloMath.dp(scorePercent: 62.5) == 95)
    }
}

// MARK: Board preferences

@MainActor
@Suite struct BoardPreferencesTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "board-\(UUID().uuidString)").unsafelyUnwrapped
    }

    @Test func startsWithTheSitesDefaultAndRemembersChoices() {
        let store = defaults()
        let preferences = BoardPreferences(defaults: store)
        #expect(preferences.theme == .standard)
        #expect(preferences.theme.isStandard)
        #expect(preferences.sound == BoardPreferences.Sound(enabled: true, volume: 0.35))
        #expect(preferences.squareColors == .brown)

        preferences.pieceSet = .chessnut
        preferences.texture = .wood
        preferences.squareColors = .green
        preferences.sound.enabled = false
        preferences.sound.volume = 0.8

        let again = BoardPreferences(defaults: store)
        #expect(again.pieceSet == .chessnut)
        #expect(again.texture == .wood)
        #expect(again.theme.lightSquare == "#eeeed2")
        #expect(again.theme.darkSquare == "#769656")
        #expect(again.sound == BoardPreferences.Sound(enabled: false, volume: 0.8))

        again.resetTheme()
        #expect(again.theme == .standard)
        #expect(again.sound.enabled == false)
    }

    @Test func storesTheSitesShapeAndRepairsBadValues() throws {
        let store = defaults()
        let preferences = BoardPreferences(defaults: store)
        preferences.texture = .fabric
        let saved = try #require(store.data(forKey: BoardPreferences.themeKey))
        let json = try #require(try JSONSerialization.jsonObject(with: saved) as? [String: String])
        #expect(json == ["pieceSet": "cburnett", "boardTexture": "canvas", "lightSquare": "#f0d9b5", "darkSquare": "#b58863"])

        let broken = ##"{"pieceSet":"staunty","boardTexture":"marble","lightSquare":"red","darkSquare":"#abc"}"##
        store.set(Data(broken.utf8), forKey: BoardPreferences.themeKey)
        store.set(Data(#"{"enabled":true,"volume":7}"#.utf8), forKey: BoardPreferences.soundKey)
        let repaired = BoardPreferences(defaults: store)
        #expect(repaired.theme == .init(pieceSet: "cburnett", boardTexture: "default", lightSquare: "#f0d9b5", darkSquare: "#abc"))
        #expect(repaired.sound.volume == 1)
        #expect(repaired.squareColors == nil)
    }

    @Test func namesThePieceDrawingsAndTheVolume() {
        let knight = Piece(.white, .knight)
        #expect(PieceSet.cburnett.assetName(knight) == "piece-wN")
        #expect(PieceSet.kaneoMidnight.assetName(Piece(.black, .queen)) == "piece-kaneo-midnight-bQ")
        #expect(HexColor.isValid("#abc"))
        #expect(!HexColor.isValid("#abcd"))
        #expect(!HexColor.isValid("f0d9b5"))
        #expect(BoardSounds.playerVolume(for: 0.35) == 0.6)
        #expect(BoardSounds.playerVolume(for: 1) == 1)
        #expect(BoardSounds.playerVolume(for: 0) == 0)
    }
}

// MARK: Move list

@Suite struct MoveListTests {
    @Test func flattensVariationsInPGNOrder() throws {
        let tree = try MoveTree(pgn: "1. e4 e5 (1... c5 2. Nf3) 2. Nf3")
        let tokens = MoveListTokens.make(tree)
        let text = tokens.map { token -> String in
            switch token.kind {
            case let .move(id, number): [number, tree[id].san].compactMap { $0 }.joined(separator: " ")
            case .open: "("
            case .close: ")"
            case let .comment(comment): "{\(comment)}"
            }
        }
        #expect(text == ["1. e4", "e5", "(", "1... c5", "2. Nf3", ")", "2. Nf3"])
        #expect(tokens.map(\.depth) == [0, 0, 1, 1, 1, 1, 0])
    }
}
