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

/// Continue with Google: the secret, its challenge, and the reading of the
/// address the sign-in sheet comes back to.
struct GoogleHandoffTests {
    /// The example of RFC 7636, appendix B.
    @Test func theChallengeIsTheOneOfTheRFC() {
        #expect(GoogleHandoff.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk") == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func aVerifierIs43CharactersOfThePKCEAlphabet() {
        let verifier = GoogleHandoff.makeVerifier()
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(verifier != GoogleHandoff.makeVerifier())
    }

    @Test func theSheetOpensTheSitesStart() throws {
        let url = GoogleHandoff.startURL(server: try #require(URL(string: "https://chessdesk.app")), challenge: "abc")
        #expect(url.absoluteString == "https://chessdesk.app/api/v1/auth/google/start?code_challenge=abc")
    }

    @Test func theWayBackIsReadStrictly() throws {
        func read(_ text: String) throws -> Result<GoogleCredential, GoogleSignInError> {
            GoogleHandoff.read(try #require(URL(string: text)), verifier: "v")
        }
        #expect(try read("chessdesk://auth/google?code=one-time") == .success(GoogleCredential(code: "one-time", codeVerifier: "v")))
        #expect(try read("chessdesk://auth/google?error=coach") == .failure(.coach))
        #expect(try read("chessdesk://auth/google?error=unavailable") == .failure(.unavailable))
        #expect(try read("chessdesk://auth/google?error=whatever") == .failure(.failed))
        #expect(try read("chessdesk://auth/google") == .failure(.failed))
        // Another address of the scheme is not this exchange.
        #expect(try read("chessdesk://auth/other?code=one-time") == .failure(.failed))
        #expect(try read("https://chessdesk.app/auth/google?code=one-time") == .failure(.failed))
    }
}

/// The summary of a review counts what the review holds, side by side.
struct GameSummaryTests {
    private func move(_ ply: Int, _ kind: MoveClass, cp: Double) -> ReviewedMove {
        ReviewedMove(
            ply: ply, san: "e4", color: ply % 2 == 1 ? "w" : "b", evalCp: cp, mate: nil, bestSan: "e4", cpl: 0, winLoss: 0,
            classification: kind
        )
    }

    private var review: GameReview {
        GameReview(
            version: 1, depth: 12, computedAt: Date(timeIntervalSince1970: 0), whiteAccuracy: 85.84, blackAccuracy: 57.3,
            moves: [move(1, .book, cp: 20), move(2, .book, cp: 20), move(3, .best, cp: 30), move(4, .blunder, cp: 300),
                    move(5, .brilliant, cp: 320), move(6, .mistake, cp: 600)]
        )
    }

    @Test func countsAreBySideAndClass() {
        #expect(GameSummaryView.count(.book, side: "w", in: review) == 1)
        #expect(GameSummaryView.count(.book, side: "b", in: review) == 1)
        #expect(GameSummaryView.count(.blunder, side: "b", in: review) == 1)
        #expect(GameSummaryView.count(.blunder, side: "w", in: review) == 0)
        #expect(GameSummaryView.count(.brilliant, side: "w", in: review) == 1)
    }

    @Test func accuracyKeepsOneDecimal() {
        #expect(GameSummaryView.accuracyText(85.84) == "85.8")
        #expect(GameSummaryView.accuracyText(100) == "100.0")
    }

    @Test func everyClassIsListedOnce() {
        #expect(Set(GameSummaryView.classes) == Set(MoveClass.allCases))
        #expect(GameSummaryView.classes.count == MoveClass.allCases.count)
    }

    /// The moves a walk-through stops on, and the ones whose SAN is coloured.
    @Test func keyMomentsAndColouredMoves() {
        #expect(MoveClass.allCases.filter(\.isKeyMoment) == [.brilliant, .great, .mistake, .blunder])
        #expect(Set(MoveClass.allCases.filter(\.coloursItsMove)) == [.brilliant, .great, .inaccuracy, .mistake, .blunder])
    }
}
