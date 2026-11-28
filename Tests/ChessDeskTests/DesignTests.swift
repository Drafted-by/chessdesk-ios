import SwiftUI
import Testing
@testable import ChessDesk

/// The path data of the emblems comes from the site as SVG: it must be read
/// as a browser reads it.
struct SVGPathTests {
    private func box(_ data: String) -> CGRect { Path(svg: data).boundingRect }

    private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

    @Test func absoluteAndRelativeLines() {
        let rect = box("M5.4 4.6H21.6V28.6H5.4Z")
        #expect(close(rect.minX, 5.4) && close(rect.minY, 4.6) && close(rect.maxX, 21.6) && close(rect.maxY, 28.6))
        let relative = box("M2 3h4v5h-4z")
        #expect(close(relative.minX, 2) && close(relative.minY, 3) && close(relative.width, 4) && close(relative.height, 5))
    }

    @Test func pairsAfterAMoveAreLines() {
        let rect = box("M28.3 28.3 22.4 22.4")
        #expect(close(rect.minX, 22.4) && close(rect.maxX, 28.3))
        let relative = box("m1 1 2 3")
        #expect(close(relative.maxX, 3) && close(relative.maxY, 4))
    }

    /// "-.4", "1.2.4" and "4.6-2.4" are each two numbers or a signed one.
    @Test func compactNumbers() {
        let rect = box("M-4.6-.4L1.2.4")
        #expect(close(rect.minX, -4.6) && close(rect.minY, -0.4) && close(rect.maxX, 1.2) && close(rect.maxY, 0.4))
    }

    @Test func aHalfCircleArc() {
        // The dial of the rating emblem: from the left end over the top.
        let rect = box("M2.6 24.6A13.4 13.4 0 0 1 29.4 24.6Z")
        #expect(close(rect.minX, 2.6) && close(rect.maxX, 29.4) && close(rect.minY, 11.2) && close(rect.maxY, 24.6))
        // Flags glued to what follows.
        let glued = box("M0 0a5 5 0 015 5")
        #expect(close(glued.maxX, 5) && close(glued.maxY, 5))
    }

    @Test func smoothCurvesReflectThePreviousControl() throws {
        // The lip of the import tray: C then S ends where it says.
        let path = Path(svg: "M3 19.4H10.8C10.8 21.6 13 23.4 16 23.4S21.2 21.6 21.2 19.4H29")
        #expect(close(path.boundingRect.maxX, 29))
        #expect(close(path.boundingRect.maxY, 23.4))
        let end = try #require(path.currentPoint)
        #expect(close(end.x, 29) && close(end.y, 19.4))
    }

    @Test func everyEmblemHasADrawing() {
        #expect(Emblem.Kind.allCases.count == 21)
    }
}

/// What leads the Train hub: the thing that waits for the player today.
struct TrainHubTests {
    @Test func aGuestIsLedToPuzzles() {
        #expect(TrainRow.lead(nil) == .puzzles)
        #expect(TrainRow.puzzles.leadCopy(nil).metric == nil)
        #expect(TrainRow.puzzles.figure(nil) == nil)
    }

    @Test func theSamplePlayerIsLedToTheirOpenDaily() throws {
        let home = try FixturePlayer().home()
        var state = TrainState(home: home)
        #expect(TrainRow.lead(state) == .daily)
        #expect(TrainRow.mistakes.figure(state) == .init(value: "9", caption: "due", isDue: true))

        // The Daily 5 done: the mistakes due lead.
        state.daily?.doneToday = true
        #expect(TrainRow.lead(state) == .mistakes)
        #expect(TrainRow.mistakes.leadCopy(state).metric?.value == "9")
        #expect(TrainRow.daily.figure(state)?.isDue == false)

        // Nothing waits: puzzles, with the rating.
        state.mistakes = .init(due: 0, total: 23, mastered: 6)
        #expect(TrainRow.lead(state) == .puzzles)
        #expect(TrainRow.puzzles.leadCopy(state).metric?.caption == "puzzle rating")
        #expect(TrainRow.mistakes.figure(state) == .init(value: "Nothing due"))
    }
}

/// The username given on first launch waits for the account, once.
struct PendingGameAccountTests {
    @Test func itIsKeptThenForgotten() throws {
        let defaults = try #require(UserDefaults(suiteName: "PendingGameAccountTests"))
        defaults.removePersistentDomain(forName: "PendingGameAccountTests")
        #expect(PendingGameAccount.load(from: defaults) == nil)

        PendingGameAccount(provider: .lichess, username: "sam_rivera").save(to: defaults)
        #expect(PendingGameAccount.load(from: defaults) == PendingGameAccount(provider: .lichess, username: "sam_rivera"))

        PendingGameAccount.clear(in: defaults)
        #expect(PendingGameAccount.load(from: defaults) == nil)
    }
}

/// Learn puts forward the courses the player follows; a guest follows none.
struct LearnLeadTests {
    @Test func aGuestFollowsNoCourse() async throws {
        let courses = try await FixtureAPI().courses(token: nil)
        #expect(LearnView.followed(courses).isEmpty)
    }

    @Test func theSamplePlayerFollowsTheirCourseWithItsMovesDue() async throws {
        let courses = FixturePlayer().courses(try await FixtureAPI().courses(token: nil))
        let mine = LearnView.followed(courses)
        #expect(mine.map(\.slug) == [FixturePlayer.courseSlug])
        #expect(LearnView.dueLine(mine) == "4 moves to review today.")
    }
}
