import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// Stubs implement only what they exercise; the rest of the puzzle API
// answers "not stubbed" (the same pattern as `ReviewTests.swift`).
extension PuzzlesAPI {
    private var notStubbed: APIError { .server(status: 401, code: "unauthorized", message: "Not stubbed.") }
    func puzzleOverview(token: String?) async throws -> PuzzleOverview { throw notStubbed }
    func freePuzzles(theme: String?, band: String?, token: String?) async throws -> FreePuzzles { throw notStubbed }
    func nextPuzzle(theme: String?, token: String) async throws -> Puzzle { throw notStubbed }
    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool, ms: Int?, token: String) async throws -> PuzzleAttempt { throw notStubbed }
    func woodpecker(token: String) async throws -> WoodpeckerOverview { throw notStubbed }
    func createWoodpeckerSet(size: Int?, theme: String?, token: String) async throws -> WoodpeckerOverview { throw notStubbed }
    func closeWoodpeckerSet(_ status: WoodpeckerSetStatus, token: String) async throws -> WoodpeckerOverview { throw notStubbed }
    func recordWoodpeckerSolve(puzzleId: String, correct: Bool, ms: Int, token: String) async throws -> WoodpeckerStep { throw notStubbed }
    func startWoodpeckerCycle(token: String) async throws -> WoodpeckerRun { throw notStubbed }
    func retireWoodpeckerPuzzle(_ puzzleId: String, token: String) async throws -> WoodpeckerStep { throw notStubbed }
    func woodpeckerReport(token: String) async throws -> WoodpeckerReport { throw notStubbed }
}

private func freeSet() throws -> FreePuzzles {
    try LiveAPI.decode(status: 200, data: FixtureAPI.data("puzzles-free"))
}

private func freePuzzle(_ id: String) throws -> Puzzle {
    try #require(try freeSet().puzzles.first { $0.id == id }, "\(id) is in the free set")
}

private func move(_ uci: String) -> Move { Move(uci: uci).unsafelyUnwrapped }

/// A clock the tests move by hand.
nonisolated private final class TestClock: @unchecked Sendable {
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(_ seconds: TimeInterval) { now += seconds }
}

// MARK: The free set

@Suite struct PuzzleFixtureTests {
    @Test func freeSetDecodesEasiestFirst() throws {
        let set = try freeSet()
        #expect(set.puzzles.count == 160)
        #expect(set.themes.map(\.id).contains("fork"))
        #expect(set.bands.map(\.id) == ["600-1000", "1000-1400", "1400-1800", "1800-2200"])
        for (earlier, later) in zip(set.puzzles, set.puzzles.dropFirst()) {
            #expect(earlier.rating <= later.rating)
        }
    }

    @Test func visitorSummaryDecodes() throws {
        let overview: PuzzleOverview = try LiveAPI.decode(status: 200, data: FixtureAPI.data("puzzles"))
        #expect(overview.player == nil)
        #expect(overview.free.puzzles == 160)
        #expect(overview.themeGroups.map(\.group).contains("Motifs"))
    }

    /// The site's `engine.test.ts`: every puzzle of the set plays start to finish.
    @Test func everyFreePuzzlePlaysToTheEnd() throws {
        for puzzle in try freeSet().puzzles {
            var solver = try #require(PuzzleSolver(puzzle), "\(puzzle.id) reads")
            #expect(!solver.isSolved)
            #expect(solver.solutionIndex == 1)
            var guardCount = 0
            while !solver.isSolved {
                guardCount += 1
                try #require(guardCount < 20, "\(puzzle.id) terminates")
                let expected = try #require(solver.expectedMove)
                let result = solver.submit(expected)
                #expect(result != .wrong && result != .illegal, "\(puzzle.id) accepts its own line")
            }
        }
    }

    @Test func fixtureFiltersLikeTheServer() async throws {
        let api = FixtureAPI(delay: .zero)
        let forks = try await api.freePuzzles(theme: "fork", band: nil, token: nil)
        #expect(!forks.puzzles.isEmpty)
        #expect(forks.puzzles.allSatisfy { $0.themes.contains { $0.id == "fork" } })
        let beginners = try await api.freePuzzles(theme: nil, band: "600-1000", token: nil)
        #expect(!beginners.puzzles.isEmpty)
        #expect(beginners.puzzles.allSatisfy { (600..<1000).contains($0.rating) })
        // chessdesk.app answered 5 puzzles for theme=fork&band=600-1000 on 28 November 2026.
        let both = try await api.freePuzzles(theme: "fork", band: "600-1000", token: nil)
        #expect(both.puzzles.count == 5)
    }
}

// MARK: Solving, ported from lib/puzzles/engine.ts

@Suite struct PuzzleSolverTests {
    @Test func startPlaysTheSetupMoveAndHandsOverTheTurn() throws {
        let puzzle = try freePuzzle("0CTn1")
        let solver = try #require(PuzzleSolver(puzzle))
        #expect(solver.solutionIndex == 1)
        #expect(solver.lastMove == move("h4h3"))
        #expect(solver.solverSide == .white)
        #expect(solver.position.fen != puzzle.fen)
        #expect(solver.hintSquare == Square("e1"))
    }

    @Test func aMateInTwoWalkthrough() throws {
        // 06Unf: g5g4 (setup), h2h8, g6h8 (reply), e4h7#.
        var solver = try #require(PuzzleSolver(try freePuzzle("06Unf")))
        #expect(solver.hintSquare == Square("h2"))
        #expect(solver.submit(move("h2h8")) == .correct(reply: move("g6h8")))
        #expect(solver.solutionIndex == 3)
        #expect(solver.lastMove == move("g6h8"))
        #expect(solver.submit(move("e4h7")) == .solved)
        #expect(solver.isSolved)
        #expect(solver.position.isCheckmate)
    }

    @Test func aWrongMoveChangesNothing() throws {
        let start = try #require(PuzzleSolver(try freePuzzle("06Unf")))
        var solver = start
        #expect(solver.submit(move("e4e5")) == .wrong)
        #expect(solver == start)
        #expect(solver.submit(move("a1a5")) == .illegal)
        #expect(solver.submit(move("h2h8")) == .correct(reply: move("g6h8")))
    }

    @Test func anyMateIsRight() throws {
        // Black's king steps into a back rank that two rooks can close.
        let line = ["g8h8", "a1a8"]
        var other = try #require(PuzzleSolver(fen: "6k1/6pp/8/8/8/8/8/RR4K1 b - - 0 1", moves: line))
        #expect(other.submit(move("b1b8")) == .solved)
        var wrong = try #require(PuzzleSolver(fen: "6k1/6pp/8/8/8/8/8/RR4K1 b - - 0 1", moves: line))
        #expect(wrong.submit(move("g1f2")) == .wrong)
    }

    @Test func aPromotionBecomesThePieceOfTheLine() throws {
        // BZDP4 ends with b7b8q. The site has no picker: the expected piece is
        // used when the squares match, whatever the board asked.
        var solver = try #require(PuzzleSolver(try freePuzzle("BZDP4")))
        #expect(solver.submit(move("a6b7")) == .correct(reply: move("b2f2")))
        #expect(solver.gradedMove(move("b7b8n")) == move("b7b8q"))
        #expect(solver.submit(move("b7b8r")) == .solved)
        #expect(solver.position[Square("b8").unsafelyUnwrapped] == Piece(.white, .queen))
    }
}

// MARK: The trainer, against a stub server

nonisolated private final class PuzzleServer: PuzzlesAPI, @unchecked Sendable {
    private let lock = NSLock()
    var queue: [Puzzle]
    var rating = 1500
    var attempts: [(id: String, solved: Bool, ms: Int?)] = []
    var served: [String] = []
    var stale = false
    var offlineOnce = false

    init(queue: [Puzzle]) { self.queue = queue }

    func puzzleOverview(token: String?) async throws -> PuzzleOverview {
        lock.withLock {
            PuzzleOverview(
                player: PuzzlePlayer(
                    rating: rating, deviation: 80, solved: 0, attempts: attempts.count,
                    last30Days: .init(attempts: attempts.count, solved: 0), history: []
                ),
                themeGroups: [PuzzleThemeGroup(group: "Motifs", themes: [PuzzleTheme(id: "fork", label: "Fork")])],
                free: .init(puzzles: 160)
            )
        }
    }

    func nextPuzzle(theme: String?, token: String) async throws -> Puzzle {
        try lock.withLock {
            guard !queue.isEmpty else { throw APIError.server(status: 404, code: "not_found", message: "No puzzle.") }
            let next = queue.removeFirst()
            served.append(next.id)
            return next
        }
    }

    func recordPuzzleAttempt(_ puzzleId: String, solved: Bool, ms: Int?, token: String) async throws -> PuzzleAttempt {
        try lock.withLock {
            if offlineOnce {
                offlineOnce = false
                throw APIError.offline
            }
            if stale || served.last != puzzleId {
                throw APIError.server(status: 409, code: "request_failed", message: "That puzzle is no longer served.")
            }
            attempts.append((puzzleId, solved, ms))
            let delta = solved ? 12 : -9
            rating += delta
            return PuzzleAttempt(rating: rating, delta: delta, deviation: 80, solved: attempts.filter(\.solved).count)
        }
    }
}

@MainActor
@Suite struct PuzzleTrainerTests {
    private func rated(_ ids: [String], clock: TestClock = TestClock()) throws -> (PuzzleTrainerModel, PuzzleServer) {
        let server = PuzzleServer(queue: try ids.map(freePuzzle))
        let model = PuzzleTrainerModel(source: .rated, api: server, token: { "token" }, now: { clock.now })
        model.wrongBeat = .zero
        model.replyDelay = .zero
        return (model, server)
    }

    @Test func aCleanSolveRaisesTheRating() async throws {
        let clock = TestClock()
        let (model, server) = try rated(["06Unf", "0CTn1"], clock: clock)
        await model.start()
        await model.settle()
        #expect(model.rating == 1500)
        #expect(model.puzzle?.id == "06Unf")
        #expect(model.movableSide == .white)
        // The setup move is on the board.
        #expect(model.board?.lastMove == move("g5g4"))

        #expect(model.play(move("h2h8")))
        #expect(model.feedback == .correct)
        await model.settle()
        // The opponent's reply was played on the board.
        #expect(model.board?.lastMove == move("g6h8"))
        clock.advance(7)
        #expect(model.play(move("e4h7")))
        #expect(model.feedback == .solved)
        #expect(model.board?.verdict == BoardVerdict(square: Square("h7").unsafelyUnwrapped, kind: .right))
        #expect(server.attempts.isEmpty, "nothing is sent before the player moves on")

        await model.next()
        #expect(server.attempts.count == 1)
        #expect(server.attempts[0].solved)
        #expect(server.attempts[0].ms == 7000)
        #expect(model.rating == 1512)
        #expect(model.lastDelta == 12)
        #expect(model.streak == 1)
        #expect(model.puzzle?.id == "0CTn1")
    }

    @Test func aWrongMoveIsRefusedAndTheSolveCountsAsFailed() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        #expect(model.play(move("e4e5")))
        #expect(model.feedback == .wrong)
        #expect(model.board?.verdict?.kind == .wrong)
        await model.settle()
        // Taken back: the player tries again.
        #expect(model.board?.verdict == nil)
        #expect(model.board?.lastMove == move("g5g4"))
        #expect(model.play(move("h2h8")))
        await model.settle()
        #expect(model.play(move("e4h7")))
        #expect(model.feedback == .completed)
        await model.next()
        #expect(server.attempts.map(\.solved) == [false])
        #expect(model.rating == 1491)
        #expect(model.lastDelta == -9)
        #expect(model.streak == 0)
    }

    @Test func aHintMakesItAMissAndRevealsTheThemes() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        #expect(!model.hintUsed)
        model.hint()
        #expect(model.hintSquare == Square("h2"))
        #expect(model.hintUsed)
        #expect(model.play(move("h2h8")))
        #expect(model.hintSquare == nil)
        await model.settle()
        #expect(model.play(move("e4h7")))
        await model.next()
        #expect(server.attempts.map(\.solved) == [false])
    }

    @Test func showingTheSolutionPlaysTheLineAndIsAMiss() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        await model.showSolution()
        #expect(model.isLineOver)
        #expect(model.feedback == .revealed)
        #expect(model.board?.position.isCheckmate == true)
        await model.next()
        #expect(server.attempts.map(\.solved) == [false])
    }

    @Test func skippingIsAMiss() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        await model.next()
        #expect(server.attempts.map(\.solved) == [false])
        #expect(model.puzzle?.id == "0CTn1")
    }

    @Test func aStaleAttemptReadsTheStateAgain() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        server.stale = true
        server.rating = 1620
        await model.next()
        #expect(model.notice != nil)
        #expect(model.submitError == nil)
        #expect(model.rating == 1620, "the rating is read again")
        #expect(model.puzzle?.id == "0CTn1", "a fresh puzzle is served")
    }

    @Test func aResultThatCouldNotBeSavedKeepsThePuzzleUp() async throws {
        let (model, server) = try rated(["06Unf", "0CTn1"])
        await model.start()
        await model.settle()
        server.offlineOnce = true
        await model.next()
        #expect(model.submitError != nil)
        #expect(model.puzzle?.id == "06Unf")
        await model.retrySubmit()
        #expect(model.submitError == nil)
        #expect(server.attempts.count == 1)
        await model.next()
        #expect(server.attempts.count == 1, "an outcome is sent once")
        #expect(model.puzzle?.id == "0CTn1")
    }

    @Test func theFreeStreakCountsFirstTimeCleanSolvesOnThisDevice() async throws {
        let defaults = try #require(UserDefaults(suiteName: "puzzles-\(UUID().uuidString)"))
        let store = FreePuzzleProgressStore(defaults: defaults)
        let model = PuzzleTrainerModel(source: .free, api: FixtureAPI(delay: .zero), token: { nil }, store: store)
        model.replyDelay = .zero
        model.wrongBeat = .zero
        await model.setFilters(theme: "mateIn1", band: nil)
        await model.settle()
        let first = try #require(model.puzzle)
        let solution = try #require(model.solver?.expectedMove)
        #expect(model.play(solution))
        #expect(model.feedback == .solved)
        #expect(model.streak == 1)
        #expect(store.streak == 1)
        #expect(store.solved == [first.id])
        await model.next()
        #expect(model.puzzle?.id != first.id)
        #expect(model.index == 1)

        // A fresh trainer reads the device's progress back.
        let again = PuzzleTrainerModel(source: .free, api: FixtureAPI(delay: .zero), token: { nil }, store: store)
        #expect(again.streak == 1)
        #expect(again.bestStreak == 1)
        #expect(again.solvedIDs == [first.id])
    }
}

// MARK: Woodpecker, against a stub server that enforces the method's rules

nonisolated private final class WoodpeckerServer: PuzzlesAPI, @unchecked Sendable {
    private let lock = NSLock()
    let puzzles: [WoodpeckerPuzzle]
    var premium = false
    var cycleLimit = 2
    var cycles: [WoodpeckerCycle] = []
    var open: (number: Int, solved: [String], ms: Int)?
    var retired: Set<String> = []
    var hasSet = false
    var solves: [(id: String, correct: Bool, ms: Int)] = []
    var closed: WoodpeckerSetStatus?

    init(_ puzzles: [Puzzle]) {
        self.puzzles = puzzles.map { WoodpeckerPuzzle(id: $0.id, fen: $0.fen, moves: $0.moves, rating: $0.rating) }
    }

    private var remaining: [WoodpeckerPuzzle] { puzzles.filter { !retired.contains($0.id) } }

    private func target(_ number: Int) -> Int? {
        guard number >= 2, let first = cycles.first else { return nil }
        return Int((Double(first.durationMs) * pow(0.5, Double(number - 1))).rounded())
    }

    private func runLocked() -> WoodpeckerRun {
        let left = remaining.filter { !(open?.solved.contains($0.id) ?? true) }
        let nextNumber = cycles.count + 1
        let state: WoodpeckerRun.NextCycle.State = cycles.count >= cycleLimit
            ? (premium ? .unavailable : .premiumRequired) : .allowed
        return WoodpeckerRun(
            set: .init(id: "set1", size: puzzles.count, theme: nil, baseRating: 1000, spread: 200,
                       createdAt: Date(timeIntervalSince1970: 0), retired: retired.count, remaining: remaining.count,
                       discovery: !premium),
            cycles: cycles,
            openCycle: open.map { .init(cycleNumber: $0.number, startedAt: Date(timeIntervalSince1970: 0),
                                        solved: $0.solved.count, total: remaining.count, targetMs: target($0.number)) },
            expectedPuzzleId: open == nil ? nil : left.first?.id,
            puzzles: open == nil ? [] : left,
            between: .init(
                nextCycle: .init(state: state, cycleNumber: nextNumber, targetMs: target(nextNumber),
                                 message: state == .allowed ? nil : "Premium adds more cycles."),
                canComplete: cycles.count >= 2, cyclesToComplete: 2, cycleLimit: cycleLimit
            )
        )
    }

    private func overviewLocked() -> WoodpeckerOverview {
        WoodpeckerOverview(
            state: hasSet ? .run : (premium ? .create : .discovery),
            premium: premium,
            calibration: .init(attempts: 50, required: 50, calibrated: true),
            discovery: .init(used: hasSet, size: 20, cycles: 2),
            completedSets: 0,
            creation: .init(sizes: .init(min: 100, max: 1000, default: 300, presets: [150, 300]), themeGroups: []),
            run: hasSet ? runLocked() : nil,
            history: []
        )
    }

    func woodpecker(token: String) async throws -> WoodpeckerOverview { lock.withLock { overviewLocked() } }

    func createWoodpeckerSet(size: Int?, theme: String?, token: String) async throws -> WoodpeckerOverview {
        try lock.withLock {
            if size != nil, !premium {
                throw APIError.server(status: 403, code: "premium_required", message: "Custom sets are part of Premium.")
            }
            hasSet = true
            open = (1, [], 0)
            return overviewLocked()
        }
    }

    func recordWoodpeckerSolve(puzzleId: String, correct: Bool, ms: Int, token: String) async throws -> WoodpeckerStep {
        try lock.withLock {
            guard var current = open else { throw APIError.server(status: 409, code: "request_failed", message: "No open cycle.") }
            let expected = remaining.first { !current.solved.contains($0.id) }?.id
            guard puzzleId == expected else {
                throw APIError.server(status: 409, code: "request_failed", message: "Out of order.")
            }
            solves.append((puzzleId, correct, ms))
            current.solved.append(puzzleId)
            current.ms += ms
            if current.solved.count == remaining.count {
                let mine = solves.suffix(current.solved.count)
                let right = mine.filter(\.correct).count
                let t = target(current.number)
                cycles.append(WoodpeckerCycle(
                    cycleNumber: current.number, durationMs: current.ms, correct: right, total: remaining.count,
                    accuracy: Double(right) / Double(remaining.count), targetMs: t, targetBeaten: t.map { current.ms <= $0 }
                ))
                open = nil
                return WoodpeckerStep(cycleDone: true, run: runLocked())
            }
            open = current
            return WoodpeckerStep(cycleDone: false, run: runLocked())
        }
    }

    func startWoodpeckerCycle(token: String) async throws -> WoodpeckerRun {
        try lock.withLock {
            guard open == nil else { throw APIError.server(status: 409, code: "request_failed", message: "A cycle is open.") }
            guard cycles.count < cycleLimit else {
                throw APIError.server(status: 403, code: "premium_required", message: "Premium adds more cycles.")
            }
            open = (cycles.count + 1, [], 0)
            return runLocked()
        }
    }

    func retireWoodpeckerPuzzle(_ puzzleId: String, token: String) async throws -> WoodpeckerStep {
        lock.withLock {
            retired.insert(puzzleId)
            return WoodpeckerStep(cycleDone: false, run: runLocked())
        }
    }

    func closeWoodpeckerSet(_ status: WoodpeckerSetStatus, token: String) async throws -> WoodpeckerOverview {
        try lock.withLock {
            if status == .completed, cycles.count < 2 {
                throw APIError.server(status: 422, code: "request_failed", message: "Complete two cycles first.")
            }
            closed = status
            hasSet = false
            open = nil
            return overviewLocked()
        }
    }

    func woodpeckerReport(token: String) async throws -> WoodpeckerReport {
        lock.withLock {
            WoodpeckerReport(setId: "set1", status: closed?.rawValue ?? "active", size: puzzles.count, theme: nil,
                             retired: retired.count, cycles: cycles, timeSavedPercent: 50, troubleSpots: [])
        }
    }
}

@MainActor
@Suite struct WoodpeckerRunTests {
    private func model(_ server: WoodpeckerServer, clock: TestClock) -> WoodpeckerModel {
        let model = WoodpeckerModel(api: server, token: { "token" }, now: { clock.now })
        model.wrongBeat = .zero
        model.solvedBeat = .zero
        model.replyDelay = .zero
        return model
    }

    /// Plays the expected line of the puzzle on the board.
    private func solve(_ model: WoodpeckerModel) async throws {
        let id = model.puzzle?.id
        while let expected = model.solver?.expectedMove, !model.ended, model.puzzle?.id == id {
            #expect(model.play(expected))
            await model.settle()
        }
        await model.settle()
    }

    @Test func aCycleInOrderWithItsClockThenTheNext() async throws {
        let clock = TestClock()
        let server = WoodpeckerServer(try ["0CTn1", "06Unf", "0Jtd7"].map(freePuzzle))
        let model = model(server, clock: clock)
        await model.load()
        #expect(model.screen == .entry)
        #expect(model.overview?.state == .discovery)

        await model.create(size: nil, theme: nil)
        await model.settle()
        #expect(model.screen == .solving)
        #expect(model.puzzle?.id == "0CTn1", "the server's order")

        // Puzzle 1, solved in 4 s.
        clock.advance(4)
        #expect(model.elapsedMs(at: clock.now) == 4000)
        try await solve(model)
        #expect(model.puzzle?.id == "06Unf")
        #expect(model.elapsedMs(at: clock.now) == 4000)

        // Puzzle 2: the first wrong move ends it, after 6 s.
        clock.advance(6)
        #expect(model.play(move("e4e5")))
        #expect(model.feedback == .wrong)
        #expect(model.ended)
        #expect(model.movableSide == nil, "no second try")
        await model.settle()
        #expect(model.puzzle?.id == "0Jtd7")
        #expect(model.elapsedMs(at: clock.now) == 10_000)

        // Puzzle 3 closes the cycle.
        clock.advance(2)
        try await solve(model)
        #expect(server.solves.map(\.id) == ["0CTn1", "06Unf", "0Jtd7"])
        #expect(server.solves.map(\.correct) == [true, false, true])
        #expect(server.solves.map(\.ms) == [4000, 6000, 2000])
        #expect(model.screen == .between)
        #expect(model.run?.cycles.first?.durationMs == 12_000)
        #expect(model.run?.between.nextCycle.state == .allowed)
        #expect(model.run?.between.nextCycle.targetMs == 6000)

        // Cycle 2 starts with its target and a fresh clock.
        await model.startNextCycle()
        await model.settle()
        #expect(model.screen == .solving)
        #expect(model.targetMs == 6000)
        #expect(model.elapsedMs(at: clock.now) == 0)
        #expect(model.puzzle?.id == "0CTn1")
    }

    @Test func pastTheFreeCyclesIsThePaywall() async throws {
        let clock = TestClock()
        let server = WoodpeckerServer(try ["0CTn1"].map(freePuzzle))
        let model = model(server, clock: clock)
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.settle()
        try await solve(model)
        await model.startNextCycle()
        await model.settle()
        try await solve(model)
        #expect(model.screen == .between)
        #expect(model.run?.between.nextCycle.state == .premiumRequired)
        #expect(model.run?.between.canComplete == true)
        #expect(!model.showsPremium)
        await model.startNextCycle()
        #expect(model.showsPremium, "403 premium_required opens the Premium sheet")
        #expect(model.screen == .between)
    }

    @Test func aCustomSetWithoutPremiumIsThePaywall() async throws {
        let server = WoodpeckerServer(try ["0CTn1"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: 300, theme: nil)
        #expect(model.showsPremium)
        #expect(model.screen == .entry)
    }

    @Test func aRuleRefusalShowsItsMessage() async throws {
        let server = WoodpeckerServer(try ["0CTn1"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.settle()
        try await solve(model)
        await model.finishSet()
        #expect(model.error == "Complete two cycles first.")
        #expect(model.screen == .between)
    }

    @Test func aRetiredPuzzleLeavesTheCycle() async throws {
        let server = WoodpeckerServer(try ["0CTn1", "06Unf"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.settle()
        #expect(model.puzzle?.id == "0CTn1")
        await model.retire()
        await model.settle()
        #expect(model.puzzle?.id == "06Unf")
        #expect(model.run?.set.retired == 1)
        #expect(server.solves.isEmpty, "no solve is recorded for a retired puzzle")
    }

    @Test func aRunThatMovedOnIsReadAgain() async throws {
        let server = WoodpeckerServer(try ["0CTn1", "06Unf"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.settle()
        // Another device answers the first puzzle meanwhile.
        _ = try await server.recordWoodpeckerSolve(puzzleId: "0CTn1", correct: true, ms: 1000, token: "token")
        #expect(model.play(move("e1g3")))
        await model.settle()
        #expect(model.screen == .solving)
        #expect(model.puzzle?.id == "06Unf", "carries on from the server's state")
    }

    @Test func finishingASetShowsItsReport() async throws {
        let server = WoodpeckerServer(try ["0CTn1"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.settle()
        try await solve(model)
        await model.startNextCycle()
        await model.settle()
        try await solve(model)
        await model.finishSet()
        #expect(server.closed == .completed)
        #expect(model.screen == .report)
        #expect(model.report?.cycles.count == 2)
        await model.closeReport()
        #expect(model.screen == .entry)
    }

    @Test func abandoningKeepsTheResults() async throws {
        let server = WoodpeckerServer(try ["0CTn1", "06Unf"].map(freePuzzle))
        let model = model(server, clock: TestClock())
        await model.load()
        await model.create(size: nil, theme: nil)
        await model.abandon()
        #expect(server.closed == .abandoned)
        #expect(model.screen == .entry)
    }

    @Test func formatsCycleTimesLikeTheSite() {
        #expect(WoodpeckerFormat.time(0) == "0:00")
        #expect(WoodpeckerFormat.time(61_499) == "1:01")
        #expect(WoodpeckerFormat.time(59_500) == "1:00")
        #expect(WoodpeckerFormat.time(3_723_000) == "1:02:03")
    }
}
