import ChessCore
import Foundation
import StockfishEngine
import Testing
@testable import ChessDesk

private func fixture<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) throws -> Value {
    try LiveAPI.decode(status: 200, data: FixtureAPI.data(name))
}

nonisolated private let capturedStages = ["fight-for-the-centre", "develop-your-pieces", "castle-early"]

@Suite struct PathFixtureTests {
    @Test func pathsAndDetailDecode() throws {
        let paths: PathsResponse = try fixture("paths")
        #expect(paths.paths.map(\.slug) == ["chess-basics", "reach-1000-elo"])
        let path: PathDetail = try fixture("path-reach-1000-elo")
        #expect(path.slug == FeaturedPath.slug)
        #expect(path.modules.count == path.totals.modules)
        #expect(path.stages.count == path.totals.stages)
        #expect(path.stages.reduce(0) { $0 + $1.exercises } == path.totals.exercises)
        // A visitor: the free stages are open, the others locked.
        #expect(path.stages.filter { $0.state != .locked }.map(\.slug) == capturedStages)
        #expect(path.stages.allSatisfy { $0.free == ($0.state != .locked) })
        #expect(path.next?.stage == capturedStages[0])
    }

    /// Exercises start from any position and may be played from either side.
    @Test(arguments: capturedStages)
    func stageSessionsReplayWithChessCore(stage: String) throws {
        let session: PathSession = try fixture("path-session-\(stage)")
        #expect(session.stage.slug == stage)
        #expect(Set(session.exercises.map(\.lineId)) == Set(session.lines.map(\.id)))
        #expect(session.learn.allSatisfy { id in session.lines.contains { $0.id == id } })
        for line in session.lines {
            let side = line.learnerSide(deck: session.side)
            var expectedFEN = line.startFen
            for step in line.steps {
                #expect(step.fenBefore == expectedFEN)
                let before = try #require(Position(fen: step.fenBefore))
                let move = try #require(Move(uci: step.uci))
                let after = try #require(before.playing(move), "\(stage) \(line.id): \(step.uci) is legal")
                #expect(after.positionKey == (try #require(Position(fen: step.fenAfter))).positionKey)
                #expect(before.san(for: move) == step.san)
                #expect(step.mine == (before.turn == side))
                expectedFEN = step.fenAfter
            }
        }
    }

    @Test func guestProgressLaysOverTheServerState() throws {
        let path: PathDetail = try fixture("path-reach-1000-elo")
        var guest = GuestProgress()
        var progress = PathProgress(path: path, guest: guest)
        #expect(progress.next?.slug == capturedStages[0])
        #expect(!progress.hasStarted)

        guest.complete(stage: capturedStages[0], path: path.slug)
        progress = PathProgress(path: path, guest: guest)
        #expect(progress.state(of: path.stages[0]) == .done)
        #expect(progress.next?.slug == capturedStages[1])
        #expect(progress.learned == path.stages[0].exercises)

        // With every free stage done, the next stage is the paywall.
        for stage in capturedStages.dropFirst() { guest.complete(stage: stage, path: path.slug) }
        progress = PathProgress(path: path, guest: guest)
        #expect(progress.next?.state == .locked)
        // A locked stage stays locked whatever the device says.
        let locked = try #require(path.stages.first { $0.state == .locked })
        guest.complete(stage: locked.slug, path: path.slug)
        #expect(PathProgress(path: path, guest: guest).state(of: locked) == .locked)
    }

    @Test func olderGuestFilesStillLoad() throws {
        let old = Data(#"{"grades":{"x":[{"fen":"a","uci":"e2e4","grade":"good"}]},"lastCourse":"x"}"#.utf8)
        let progress = try JSONDecoder().decode(GuestProgress.self, from: old)
        #expect(progress.learnedMoves(course: "x") == 1)
        #expect(progress.completedStages.isEmpty)
    }
}

/// An engine that answers from a table, by FEN.
private struct TableEngine: PositionEvaluating {
    var table: [String: EngineEvaluation] = [:]

    func evaluate(fen: String) async throws -> EngineEvaluation {
        guard let found = table[fen] else { throw EngineError.notStarted }
        return found
    }
}

private func score(cp: Int? = nil, mate: Int? = nil) -> EngineEvaluation {
    EngineEvaluation(centipawns: cp, mate: mate, depth: 12, principalVariation: [])
}

@Suite struct EngineJudgeTests {
    @Test func aMoveWithin35CentipawnsIsAsGood() async {
        // Scores are the opponent's, after each move: lower is better for the learner.
        let judge = EngineJudge(engine: TableEngine(table: ["played": score(cp: -180), "expected": score(cp: -200), "worse": score(cp: -150)]))
        #expect(await judge.accepts(.equal(fenAfterPlayed: "played", fenAfterExpected: "expected")))
        #expect(await judge.accepts(.equal(fenAfterPlayed: "expected", fenAfterExpected: "played")))
        #expect(await !judge.accepts(.equal(fenAfterPlayed: "worse", fenAfterExpected: "expected")))
    }

    @Test func aMateMustStayOnSchedule() async {
        let judge = EngineJudge(engine: TableEngine(table: ["in1": score(mate: -1), "in3": score(mate: -3), "none": score(cp: -900), "lost": score(mate: 2)]))
        #expect(await judge.accepts(.mate(fenAfterPlayed: "in1", within: 1)))
        #expect(await judge.accepts(.mate(fenAfterPlayed: "in1", within: 2)))
        #expect(await !judge.accepts(.mate(fenAfterPlayed: "in3", within: 2)))
        #expect(await !judge.accepts(.mate(fenAfterPlayed: "none", within: 2)))
        #expect(await !judge.accepts(.mate(fenAfterPlayed: "lost", within: 2)))
        #expect(await judge.accepts(.accepted))
    }

    @Test func withoutTheEngineOnlyTheCourseMoveCounts() async {
        let judge = EngineJudge(engine: TableEngine())
        #expect(await !judge.accepts(.equal(fenAfterPlayed: "a", fenAfterExpected: "b")))
    }

    /// The real engine, in the simulator, on an exercise of the course.
    @Test func stockfishRunsOnTheDevice() async throws {
        let network = try #require(DeviceEngine.networkURL, "the network is in the app bundle (scripts/fetch-nnue.sh)")
        #expect(network.lastPathComponent == StockfishEngine.networkName)
        let mate = try await DeviceEngine().evaluate(fen: "6k1/4Rppp/8/8/8/8/5PPP/6K1 w - - 0 1")
        #expect(mate.mate == 1)
        #expect(mate.bestMove == "e7e8")
    }
}

/// A judge with a fixed answer, which records what it was asked.
private final class FixedJudge: MoveJudging, @unchecked Sendable {
    let answer: Bool
    private let lock = NSLock()
    private var asked: [JudgeQuestion] = []

    init(_ answer: Bool) { self.answer = answer }

    var questions: [JudgeQuestion] { lock.withLock { asked } }

    func accepts(_ question: JudgeQuestion) async -> Bool {
        lock.withLock { asked.append(question) }
        return answer
    }
}

private func settle(until done: () -> Bool) async {
    for _ in 0..<400 where !done() {
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(1))
    }
}

@Suite @MainActor struct PathTrainerTests {
    private func line(_ stage: String, _ index: Int) throws -> (TrainingLine, PathSession.Exercise, Side) {
        let session: PathSession = try fixture("path-session-\(stage)")
        let line = session.lines[index]
        let exercise = try #require(session.exercises.first { $0.lineId == line.id })
        return (line, exercise, line.learnerSide(deck: session.side))
    }

    private func model(_ stage: String, _ index: Int, judge: (any MoveJudging)? = nil) throws -> LineTrainerModel {
        let (line, exercise, side) = try line(stage, index)
        let model = LineTrainerModel(line: line, side: side, flow: exercise.flow)
        model.timing = .immediate
        model.judge = judge
        return model
    }

    private func expected(_ model: LineTrainerModel) throws -> Move {
        let step = try #require(model.currentStep)
        return try #require(Move(uci: step.uci))
    }

    private func otherMove(_ model: LineTrainerModel, mating: Bool = false) throws -> Move {
        let wanted = model.position.normalized(try expected(model))
        return try #require(model.position.legalMoves().first { move in
            move != wanted && (model.position.playing(move)?.isCheckmate ?? false) == mating
        })
    }

    @Test func aLessonIsDoneOncePlayedThrough() async throws {
        let model = try model("fight-for-the-centre", 0)
        #expect(model.flow == .lesson)
        #expect(model.phase == .guided)
        var reported: [MoveGrade] = []
        model.onFinished = { reported = $0 }
        model.start()
        while model.phase == .guided {
            await settle { model.isOurTurn || model.phase == .finished }
            if model.phase == .finished { break }
            #expect(model.play(try expected(model)))
        }
        await settle { model.phase == .finished }
        #expect(model.phase == .finished)
        #expect(reported.count == model.ourMoveCount)
        #expect(reported.allSatisfy { $0.grade == .good })
    }

    @Test func solvingStartsWithoutTheAnswerAndExplainsOnceFound() async throws {
        let model = try model("fight-for-the-centre", 1)
        #expect(model.flow == .solve)
        #expect(model.phase == .play)
        model.start()
        await settle { model.isOurTurn }
        #expect(model.arrows.isEmpty)
        #expect(model.solvedStep == nil)

        #expect(model.play(try otherMove(model)))
        #expect(model.feedback == .missed)
        #expect(!model.noteRevealed, "the note explains the answer: it waits for the move")
        await settle { !model.isBoardLocked }

        #expect(model.play(try expected(model)))
        #expect(model.solvedStep?.uci == model.steps.last { $0.mine }?.uci)
        await settle { model.phase == .finished }
        #expect(model.grades.map(\.grade) == [.again])
    }

    @Test func theEngineMayAcceptAnotherLastMove() async throws {
        let judge = FixedJudge(true)
        let model = try model("fight-for-the-centre", 1, judge: judge)
        model.start()
        await settle { model.isOurTurn }
        let step = try #require(model.currentStep)
        let other = try otherMove(model)
        let fenAfterOther = try #require(model.position.playing(other)).fen
        #expect(model.play(other))
        #expect(model.isJudging)
        await settle { model.phase == .finished }
        #expect(judge.questions == [.equal(fenAfterPlayed: fenAfterOther, fenAfterExpected: step.fenAfter)])
        #expect(model.solvedAnotherWay)
        #expect(model.grades.map(\.grade) == [.good])
    }

    @Test func aRefusedMoveIsAMiss() async throws {
        let model = try model("fight-for-the-centre", 1, judge: FixedJudge(false))
        model.start()
        await settle { model.isOurTurn }
        let home = model.position
        #expect(model.play(try otherMove(model)))
        await settle { !model.isJudging && !model.isBoardLocked }
        #expect(model.position == home)
        #expect(model.feedback == .missed)
        #expect(!model.solvedAnotherWay)
    }

    /// "Castling: a night at the opera" ends in mate, with two moves of ours.
    @Test func inAMatingExerciseTheEngineIsAskedForTheSchedule() async throws {
        let judge = FixedJudge(false)
        let model = try model("castle-early", 3, judge: judge)
        #expect(model.steps.last?.san.hasSuffix("#") == true)
        model.start()
        await settle { model.isOurTurn }
        let other = try otherMove(model)
        let fenAfterOther = try #require(model.position.playing(other)).fen
        #expect(model.play(other))
        await settle { !model.isJudging && !model.isBoardLocked }
        #expect(judge.questions == [.mate(fenAfterPlayed: fenAfterOther, within: 1)])
    }
}
