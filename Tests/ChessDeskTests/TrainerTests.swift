import ChessCore
import Foundation
import Testing
@testable import ChessDesk

private func caroKannLine() throws -> (TrainingLine, Side) {
    let session: CourseSession = try LiveAPI.decode(
        status: 200, data: FixtureAPI.data("session-learn-practical-caro-kann")
    )
    return (try #require(session.lines.first), session.side)
}

private func makeModel(review: [Int]? = nil) throws -> LineTrainerModel {
    let (line, side) = try caroKannLine()
    let model = LineTrainerModel(line: line, side: side, review: review)
    model.timing = .immediate
    return model
}

private func move(_ uci: String) throws -> Move {
    try #require(Move(uci: uci))
}

private func expectedMove(_ model: LineTrainerModel) throws -> Move {
    let step = try #require(model.currentStep)
    return try move(step.uci)
}

/// A legal move that is not the line's.
private func wrongMove(_ model: LineTrainerModel) throws -> Move {
    let expected = model.position.normalized(try expectedMove(model))
    return try #require(model.position.legalMoves().first { $0 != expected })
}

@Suite @MainActor struct LineTrainerModelTests {
    @Test func guidedPassWaitsForOurMovesAndPlaysTheReplies() async throws {
        let model = try makeModel()
        #expect(model.side == .black)
        model.start()
        // White's first move plays by itself, then the board waits for us.
        await settled { model.isOurTurn }
        #expect(model.cursor == 1)
        #expect(model.arrows.count == 1)
        #expect(model.leadStep?.san == "c6")
        #expect(model.trailingStep?.san == "e4")

        while !model.guidedPassDone {
            await settled { model.isOurTurn || model.guidedPassDone }
            if model.guidedPassDone { break }
            #expect(model.play(try expectedMove(model)))
        }
        #expect(model.cursor == model.steps.count)
        #expect(model.phase == .guided)
        #expect(model.grades.isEmpty)
    }

    @Test func guidedWrongMoveIsHeldThenTakenBackAndNeverGraded() async throws {
        let model = try makeModel()
        model.start()
        await settled { model.isOurTurn }
        let home = model.position
        #expect(model.play(try wrongMove(model)))
        #expect(model.feedback == .notThisOne)
        await settled { !model.isBoardLocked }
        #expect(model.position == home)
        #expect(model.verdict == nil)
        #expect(model.cursor == 1)
    }

    @Test func backReturnsToOurPreviousMove() async throws {
        let model = try makeModel()
        model.start()
        await settled { model.isOurTurn }
        #expect(!model.canGoBack)
        #expect(model.play(try expectedMove(model)))
        await settled { model.isOurTurn }
        #expect(model.cursor == 3)
        #expect(model.canGoBack)
        model.back()
        #expect(model.cursor == 1)
        #expect(model.position.fen == model.steps[1].fenBefore)
        #expect(model.lastMove == Move(uci: "e2e4"))
    }

    @Test func memoryPassGradesMissesAndHintsAsAgain() async throws {
        let model = try makeModel()
        var reported: [MoveGrade] = []
        model.onFinished = { reported = $0 }
        model.startMemoryPass()
        var ourMove = 0
        while model.phase == .play {
            await settled { model.isOurTurn || model.phase == .finished }
            if model.phase == .finished { break }
            #expect(model.arrows.isEmpty, "no arrow from memory")
            #expect(model.leadStep == nil, "no note from memory")
            if ourMove == 0 {
                #expect(model.play(try wrongMove(model)))
                #expect(model.feedback == .missed)
                await settled { !model.isBoardLocked }
                #expect(model.leadStep != nil, "the note shows after a miss")
            }
            if ourMove == 1 {
                model.hint()
                #expect(model.hintSquare != nil)
                model.hint()
                #expect(model.arrows.count == 1)
            }
            #expect(model.play(try expectedMove(model)))
            ourMove += 1
        }
        await settled { model.phase == .finished }
        #expect(model.phase == .finished)
        #expect(reported.count == model.ourMoveCount)
        #expect(reported.prefix(2).allSatisfy { $0.grade == .again })
        #expect(reported.dropFirst(2).allSatisfy { $0.grade == .good })
        // Grades name the position before the move, as the site's trainer does.
        #expect(reported[0].fen == model.steps[1].fenBefore)
        #expect(reported[0].uci == model.steps[1].uci)
    }

    @Test func reviewStartsFromMemoryAndGradesOnlyDueMoves() async throws {
        let model = try makeModel(review: [3])
        #expect(model.phase == .play)
        #expect(model.isReview)
        model.start()
        while model.phase == .play {
            await settled { model.isOurTurn || model.phase == .finished }
            if model.phase == .finished { break }
            #expect(model.play(try expectedMove(model)))
        }
        await settled { model.phase == .finished }
        #expect(model.grades.map(\.uci) == [model.steps[3].uci])
        #expect(model.grades.first?.grade == .good)
    }
}

@Suite struct PieceLayoutTests {
    @Test func movedPieceKeepsItsIdentity() throws {
        var nextID = 0
        let start = PieceLayout.reconcile([], with: .start, nextID: &nextID)
        #expect(start.count == 32)
        #expect(nextID == 32)

        let afterE4 = try #require(Position.start.playing(try move("e2e4")))
        let moved = PieceLayout.reconcile(start, with: afterE4, nextID: &nextID)
        #expect(nextID == 32, "no new piece for a simple move")
        let pawnID = try #require(start.first { $0.square == Square("e2") }?.id)
        #expect(moved.first { $0.id == pawnID }?.square == Square("e4"))
        #expect(moved.count == 32)
    }

    @Test func captureRemovesThePieceAndCastlingMovesBoth() throws {
        var nextID = 0
        let before = try #require(Position(fen: "r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4"))
        let placed = PieceLayout.reconcile([], with: before, nextID: &nextID)
        let castled = try #require(before.playing(try move("e1g1")))
        let after = PieceLayout.reconcile(placed, with: castled, nextID: &nextID)
        let kingID = try #require(placed.first { $0.square == Square("e1") }?.id)
        let rookID = try #require(placed.first { $0.square == Square("h1") }?.id)
        #expect(after.first { $0.id == kingID }?.square == Square("g1"))
        #expect(after.first { $0.id == rookID }?.square == Square("f1"))
        #expect(after.count == placed.count)
    }
}

@Suite @MainActor struct GuestProgressTests {
    @Test func latestGradeReplacesTheEarlierOne() {
        var progress = GuestProgress()
        progress.record([MoveGrade(fen: "a", uci: "e2e4", grade: .again)], course: "x")
        progress.record([MoveGrade(fen: "a", uci: "e2e4", grade: .good), MoveGrade(fen: "b", uci: "d2d4", grade: .again)], course: "x")
        #expect(progress.grades["x"]?.count == 2)
        #expect(progress.learnedMoves(course: "x") == 1)
        #expect(progress.learnedMoves(course: "y") == 0)
    }

    @Test func storeRoundTrips() {
        let url = FileManager.default.temporaryDirectory.appending(path: "cd-test-\(UUID().uuidString)/guest.json")
        let store = GuestProgressStore(url: url)
        #expect(store.load() == GuestProgress())
        var progress = GuestProgress()
        progress.lastCourse = "practical-caro-kann"
        progress.record([MoveGrade(fen: "a", uci: "e2e4", grade: .good)], course: "practical-caro-kann")
        store.save(progress)
        #expect(store.load() == progress)
    }
}
