import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// MARK: The contract

/// The repertoire and explorer models against the site's contract.
@Suite struct RepertoireContractTests {
    private func decode<Value: Decodable>(_ name: String, as type: Value.Type) throws {
        for nulls in [false, true] {
            let data = try JSONSerialization.data(withJSONObject: try Contract.example(name, nulls: nulls))
            do {
                _ = try APICoding.decoder.decode(Value.self, from: data)
            } catch {
                Issue.record("\(name) does not decode from its contract example\(nulls ? " with nulls" : ""): \(error)")
            }
        }
    }

    @Test func modelsDecodeContractExamples() throws {
        try decode("Repertoires", as: RepertoireList.self)
        try decode("RepertoireCard", as: RepertoireCard.self)
        try decode("RepertoireDetail", as: RepertoireDetail.self)
        try decode("RepertoireNode", as: RepertoireNode.self)
        try decode("RepertoirePosition", as: RepertoirePosition.self)
        try decode("RepertoireAdherence", as: RepertoireAdherence.self)
        try decode("RepertoireImport", as: RepertoireImport.self)
        try decode("RepertoireSeed", as: RepertoireSeed.self)
        try decode("ExplorerSummary", as: ExplorerSummary.self)
        try decode("ExplorerPosition", as: ExplorerPosition.self)
        // A repertoire session has the shape the trainer already reads.
        try decode("CourseSession", as: CourseSession.self)
        try decode("DueSummary", as: DueSummary.self)
    }

    @Test func contractServesEveryRouteTheAppCalls() throws {
        let paths = try Contract.paths()
        let used: [(String, [String])] = [
            ("/api/v1/repertoires", ["get", "post"]),
            ("/api/v1/repertoires/{id}", ["get", "patch", "delete"]),
            ("/api/v1/repertoires/{id}/moves", ["post", "patch", "delete"]),
            ("/api/v1/repertoires/{id}/pgn", ["put"]),
            ("/api/v1/repertoires/{id}/seed", ["post"]),
            ("/api/v1/repertoires/{id}/session", ["get"]),
            ("/api/v1/repertoires/{id}/position", ["get"]),
            ("/api/v1/repertoires/{id}/adherence", ["get"]),
            ("/api/v1/explorer", ["get"]),
            ("/api/v1/explorer/position", ["get"]),
            ("/api/v1/training/grades", ["post"]),
        ]
        for (path, methods) in used {
            let operations = try #require(paths[path] as? [String: Any], "\(path) is in the contract")
            for method in methods { #expect(operations[method] != nil, "\(method) \(path) is in the contract") }
        }
    }

    @Test func requestBodiesAreWhatTheContractReads() throws {
        func problems(_ body: some Encodable, _ schema: String) throws -> [String] {
            try Contract.problems(in: try Contract.json(body), against: schema)
        }
        #expect(try problems(CreateRepertoireRequest(name: "Caro-Kann", color: "BLACK"), "CreateRepertoireRequest") == [])
        #expect(try problems(RenameRepertoireRequest(name: "Caro-Kann"), "RenameRepertoireRequest") == [])
        #expect(try problems(RepertoireLineRequest(line: ["e2e4", "e7e5", "e7e8q"]), "RepertoireLineRequest") == [])
        #expect(try problems(ImportRepertoirePgnRequest(pgn: "1. e4 e5"), "ImportRepertoirePgnRequest") == [])
        let annotate = AnnotateRepertoireMoveRequest(path: ["e2e4"], comment: "Central.", glyph: .set(1))
        #expect(try problems(annotate, "AnnotateRepertoireMoveRequest") == [])
        // A move the server would refuse is caught by the same check.
        #expect(try problems(RepertoireLineRequest(line: ["e4"]), "RepertoireLineRequest") != [])
    }

    /// A field left out is kept, null clears it: the three states of the glyph.
    @Test func theGlyphIsKeptClearedOrSet() throws {
        func body(_ request: AnnotateRepertoireMoveRequest) throws -> [String: Any] {
            try #require(try Contract.json(request) as? [String: Any])
        }
        let kept = try body(AnnotateRepertoireMoveRequest(path: ["e2e4"], comment: nil, glyph: .keep))
        #expect(Set(kept.keys) == ["path"])
        let cleared = try body(AnnotateRepertoireMoveRequest(path: ["e2e4"], comment: "", glyph: .clear))
        #expect(cleared["nag"] is NSNull)
        #expect(cleared["comment"] as? String == "")
        let set = try body(AnnotateRepertoireMoveRequest(path: [], comment: "Before move one.", glyph: .set(3)))
        #expect(set["nag"] as? Int == 3)
        #expect((set["path"] as? [String]) == [])
    }

    @Test func queriesUseTheParametersOfTheContract() throws {
        let position = LiveAPI.repertoirePositionQuery(path: ["e2e4", "e7e5"], ratings: "1400")
        #expect(position.map(\.name) == ["path", "ratings"])
        #expect(position.first?.value == "e2e4,e7e5")
        #expect(try Set(position.map(\.name)).isSubset(of: Contract.queryParameters("/api/v1/repertoires/{id}/position", "get")))
        // The start position is no path at all.
        #expect(LiveAPI.repertoirePositionQuery(path: [], ratings: nil).isEmpty)

        var filters = ExplorerFilters(side: .black)
        filters.timeClasses = ["RAPID", "BLITZ"]
        filters.rated = .rated
        filters.dateFrom = "2026-01-01"
        filters.dateTo = "2026-11-28"
        filters.opponentMin = 800
        filters.opponentMax = 1200
        filters.source = .lichess
        let explorer = LiveAPI.explorerQuery(path: ["e4", "c6"], filters: filters, games: 20)
        let values = Dictionary(uniqueKeysWithValues: explorer.map { ($0.name, $0.value ?? "") })
        #expect(values == [
            "side": "black", "path": "e4,c6", "tc": "BLITZ,RAPID", "rated": "rated", "from": "2026-01-01",
            "to": "2026-11-28", "min": "800", "max": "1200", "source": "LICHESS", "games": "20",
        ])
        #expect(try Set(values.keys).isSubset(of: Contract.queryParameters("/api/v1/explorer/position", "get")))
        // Nothing but the colour when nothing is filtered.
        #expect(LiveAPI.explorerQuery(path: [], filters: ExplorerFilters(), games: nil).map(\.name) == ["side"])
        #expect(try Contract.queryParameters("/api/v1/repertoires/{id}/moves", "delete") == ["path"])
        #expect(try Contract.queryParameters("/api/v1/repertoires/{id}/session", "get") == ["mode"])
    }

    /// A check in a SAN path must not reach the server as a space.
    @Test func aCheckInAPathIsPercentEncoded() throws {
        let api = LiveAPI(baseURL: try #require(URL(string: "https://chessdesk.app")))
        let query = LiveAPI.explorerQuery(path: ["e4", "e5", "Bb5+", "Qxf7#", "e8=Q"], filters: ExplorerFilters(), games: nil)
        let request = api.request("GET", "explorer/position", query: query, token: "abc")
        let url = LiveAPI.strictQuery(try #require(request.url))
        #expect(url.absoluteString.contains("Bb5%2B"))
        #expect(!url.absoluteString.contains("+"))
        #expect(!url.absoluteString.contains("#"))
        // What the server reads back is the path that was sent.
        let read = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "path" }?.value
        #expect(read == "e4,e5,Bb5+,Qxf7#,e8=Q")
        let moves = api.request(
            "DELETE", "repertoires/rep1/moves", query: [URLQueryItem(name: "path", value: "e2e4,e7e5")], token: "abc"
        )
        #expect(moves.url?.absoluteString == "https://chessdesk.app/api/v1/repertoires/rep1/moves?path=e2e4,e7e5")
        #expect(moves.httpMethod == "DELETE")
    }
}

// MARK: The tree

@Suite struct RepertoireTreeTests {
    /// A node holds its children, which hold theirs: a line of 200 half-moves
    /// (100 moves, far past any opening) with a branch at every step decodes.
    @Test func aDeepTreeDecodes() throws {
        func node(_ depth: Int, of total: Int) -> [String: Any] {
            var children: [[String: Any]] = []
            if depth < total {
                children.append(node(depth + 1, of: total))
                children.append(["san": "a\(depth)", "uci": "a2a3", "fen": "f", "ply": depth + 1, "comments": [], "nags": [], "shapes": [], "children": []])
            }
            return [
                "san": "m\(depth)", "uci": "e2e4", "fen": "fen \(depth)", "ply": depth,
                "comments": depth == 3 ? ["A note."] : [], "nags": depth == 3 ? [1] : [],
                "shapes": depth == 3 ? [["brush": "green", "orig": "e2", "dest": "e4"], ["brush": "red", "orig": "d5"]] : [],
                "children": children,
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: [node(1, of: 200)])
        let tree = try APICoding.decoder.decode([RepertoireNode].self, from: data)
        var depth = 0
        var cursor = tree.first
        while let current = cursor {
            depth += 1
            cursor = current.children.first
        }
        #expect(depth == 200)
        #expect(RepertoireTree.moveCount(tree) == 200 + 199)
        #expect(RepertoireTree.lineCount(tree) == 200)
        #expect(RepertoireTree.mainLine(from: [], in: tree).count == 200)
        let third = try #require(tree.first?.children.first?.children.first)
        #expect(third.comments == ["A note."])
        #expect(third.shapes.map(\.dest) == ["e4", nil])
        // And it is written back as it was read.
        let again = try APICoding.decoder.decode([RepertoireNode].self, from: APICoding.encoder.encode(tree))
        #expect(again == tree)
    }

    @Test func aPathNamesAPosition() throws {
        let tree = tree("e4 e5 Nf3 Nc6 Bc4", "e4 e5 Nf3 d6", "e4 c5")
        #expect(RepertoireTree.moveCount(tree) == 7)
        #expect(RepertoireTree.lineCount(tree) == 3)
        #expect(RepertoireTree.node(at: uci("e4 e5 Nf3"), in: tree)?.san == "Nf3")
        #expect(RepertoireTree.children(at: uci("e4 e5 Nf3"), in: tree)?.map(\.san) == ["Nc6", "d6"])
        #expect(RepertoireTree.children(at: [], in: tree)?.map(\.san) == ["e4"])
        #expect(RepertoireTree.children(at: uci("d4"), in: tree) == nil)
        #expect(RepertoireTree.longestPrefix(of: uci("e4 e5 Bc4 Nf6"), in: tree) == uci("e4 e5"))
        #expect(RepertoireTree.mainLine(from: uci("e4"), in: tree).map(\.san) == ["e5", "Nf3", "Nc6", "Bc4"])
        // The positions are the ones ChessCore reaches, numbered from move one.
        let knight = try #require(RepertoireTree.node(at: uci("e4 e5 Nf3"), in: tree))
        #expect(knight.ply == 3)
        #expect(knight.fen == "rnbqkbnr/pppp1ppp/8/4p3/4P3/5N2/PPPP1PPP/RNBQKB1R b KQkq - 1 2")
    }

    @Test func theOutlineOpensARowAtEveryChoice() {
        let rows = RepertoireTree.outline(tree("e4 e5 Nf3 Nc6 Bc4", "e4 e5 Nf3 d6 d4", "e4 c5 Nf3"))
        #expect(rows.map(\.depth) == [0, 1, 2, 2, 1])
        #expect(rows.map { $0.moves.map(\.san) } == [["e4"], ["e5", "Nf3"], ["Nc6", "Bc4"], ["d6", "d4"], ["c5", "Nf3"]])
        #expect(rows[2].moves[0].path == uci("e4 e5 Nf3 Nc6"))
        #expect(rows.allSatisfy { $0.moves.first?.opensRow == true })
        #expect(RepertoireTree.number(ply: 3, opensRow: false) == "2.")
        #expect(RepertoireTree.number(ply: 4, opensRow: true) == "2…")
        #expect(RepertoireTree.number(ply: 4, opensRow: false) == nil)
        #expect(RepertoireTree.glyph([3]) == "!!")
        #expect(RepertoireTree.glyph([6]) == "?!")
        #expect(RepertoireTree.glyph([]) == "")
    }

    @Test func changesFollowWhatIsThereAndRefuseWhatIsNot() throws {
        let start = tree("e4 e5 Nf3")
        let same = try #require(RepertoireTree.adding(line: uci("e4 e5"), to: start, startFen: Position.startFEN))
        #expect(same.added == 0)
        let more = try #require(RepertoireTree.adding(line: uci("e4 e5 Nf3 Nc6 Bb5"), to: start, startFen: Position.startFEN))
        #expect(more.added == 2)
        #expect(RepertoireTree.adding(line: ["e2e4", "e2e4"], to: start, startFen: Position.startFEN) == nil)
        let cut = try #require(RepertoireTree.removing(path: uci("e4 e5"), from: more.tree))
        #expect(RepertoireTree.moveCount(cut) == 1)
        #expect(RepertoireTree.removing(path: uci("d4"), from: start) == nil)
    }
}

// MARK: The sample player

/// The sample data plays a signed-in player. Its answers must have the
/// shapes of the contract and follow the rules the screens rely on.
@Suite(.samplePlayer()) struct FixtureOpeningsTests {
    private let api = FixtureAPI(delay: .zero)
    private let id = "sample-italian"

    private func expectContract(_ value: some Encodable, _ schema: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let problems = try Contract.problems(in: try Contract.json(value), against: schema)
        #expect(problems == [], "\(schema)", sourceLocation: sourceLocation)
    }

    @Test(.samplePlayer(premium: true)) func answersHaveTheShapesOfTheContract() async throws {
        try expectContract(try await api.repertoires(token: "t"), "Repertoires")
        let detail = try await api.repertoire(id: id, token: "t")
        try expectContract(detail, "RepertoireDetail")
        #expect(detail.moves == 35)
        #expect(detail.lines == 6)
        for path in ["", "e4", "e4 e5 Nf3", "e4 e5 Nf3 Nc6 Bc4", "d4 d5 c4"] {
            try expectContract(try await api.repertoirePosition(id: id, path: uci(path), ratings: nil, token: "t"), "RepertoirePosition")
        }
        try expectContract(try await api.repertoireSession(id: id, mode: .learn, token: "t"), "CourseSession")
        try expectContract(try await api.repertoireSession(id: id, mode: .review, token: "t"), "CourseSession")
        try expectContract(try await api.repertoireAdherence(id: id, token: "t"), "RepertoireAdherence")
        try expectContract(try await api.explorerSummary(token: "t"), "ExplorerSummary")
        for path in [[], ["e4"], ["e4", "e5", "Nf3", "Nc6"]] {
            let position = try await api.explorerPosition(path: path, filters: ExplorerFilters(), games: nil, token: "t")
            try expectContract(position, "ExplorerPosition")
        }
        let created = try await api.createRepertoire(name: "Caro-Kann", color: "BLACK", token: "t")
        try expectContract(created, "RepertoireDetail")
        try expectContract(try await api.importRepertoirePGN(id: created.id, pgn: "1. e4 c6 2. d4 d5", token: "t"), "RepertoireImport")
        try expectContract(try await api.seedRepertoire(id: created.id, token: "t"), "RepertoireSeed")
    }

    @Test func theFreePlanHoldsOneRepertoireOfTwentyLines() async throws {
        let list = try await api.repertoires(token: "t")
        #expect(list.repertoires.map(\.id) == [id])
        #expect(!list.canCreate)
        #expect(list.top == id)
        #expect(list.totalDue == 3)
        await #expect(throws: FixtureData.freeLimit) {
            _ = try await api.createRepertoire(name: "Second", color: "BLACK", token: "t")
        }
        await #expect(throws: APIError.self) { _ = try await api.repertoireAdherence(id: id, token: "t") }
        // Six lines are there; fourteen more fit, the fifteenth is the paywall.
        let replies = ["a6", "a5", "b6", "b5", "d6", "d5", "f6", "f5", "g6", "g5", "h6", "h5", "Nf6", "Nc6", "Na6"]
        for (index, reply) in replies.enumerated() {
            let line = uci("d4 \(reply)")
            if index < 14 {
                #expect(try await api.addRepertoireLine(id: id, line: line, token: "t").lines == 7 + index)
            } else {
                await #expect(throws: FixtureData.freeLimit) { _ = try await api.addRepertoireLine(id: id, line: line, token: "t") }
            }
        }
        #expect(try await api.repertoire(id: id, token: "t").lineLimit == 20)
    }

    @Test func theTreeChangesOneMoveAtATime() async throws {
        let added = try await api.addRepertoireLine(id: id, line: uci("e4 e5 Nf3 Nf6 Nxe5"), token: "t")
        #expect(added.moves == 37)
        #expect(added.lines == 7)
        // A line that is already there changes nothing.
        #expect(try await api.addRepertoireLine(id: id, line: uci("e4 e5"), token: "t").moves == 37)
        await #expect(throws: FixtureData.refused("That move is not legal in this position.")) {
            _ = try await api.addRepertoireLine(id: id, line: ["e2e4", "e2e5"], token: "t")
        }
        let noted = try await api.annotateRepertoireMove(
            id: id, path: uci("e4 e5 Nf3 Nf6"), comment: " The Petrov. ", glyph: .set(5), token: "t"
        )
        let petrov = try #require(RepertoireTree.node(at: uci("e4 e5 Nf3 Nf6"), in: noted.tree))
        #expect(petrov.comments == ["The Petrov."])
        #expect(petrov.nags == [5])
        // A field left out is kept; an empty note removes it.
        let kept = try await api.annotateRepertoireMove(id: id, path: uci("e4 e5 Nf3 Nf6"), comment: nil, glyph: .clear, token: "t")
        #expect(RepertoireTree.node(at: uci("e4 e5 Nf3 Nf6"), in: kept.tree)?.comments == ["The Petrov."])
        #expect(RepertoireTree.node(at: uci("e4 e5 Nf3 Nf6"), in: kept.tree)?.nags == [])
        let root = try await api.annotateRepertoireMove(id: id, path: [], comment: "A new start.", glyph: .keep, token: "t")
        #expect(root.rootComment == "A new start.")
        let removed = try await api.removeRepertoireMove(id: id, path: uci("e4 e5 Nf3 Nf6"), token: "t")
        #expect(removed.moves == 35)
        await #expect(throws: FixtureData.moveNotFound) {
            _ = try await api.removeRepertoireMove(id: id, path: uci("e4 e5 Nf3 Nf6"), token: "t")
        }
        await #expect(throws: FixtureData.notFound) { _ = try await api.repertoire(id: "nobody", token: "t") }
    }

    @Test func aPGNWithVariationsBecomesOneTree() async throws {
        let pgn = """
        [Event "Chapter 1"]

        {Play the centre.} 1. d4 d5 2. c4 $1 {The gambit.} e6 (2... c6 3. Nf3 Nf6) (2... dxc4 3. e3) 3. Nc3 Nf6 *

        [Event "Chapter 2"]

        1. d4 Nf6 2. c4 g6 0-1

        [Event "From a position"]
        [FEN "8/8/8/3k4/8/3K4/8/8 w - - 0 1"]

        1. Ke3 *
        """
        let result = try await api.importRepertoirePGN(id: id, pgn: pgn, token: "t")
        #expect(result.merged == 2)
        #expect(result.skipped == 1)
        #expect(result.repertoire.lines == 4)
        #expect(result.repertoire.rootComment == "Play the centre.")
        let gambit = try #require(RepertoireTree.node(at: uci("d4 d5 c4"), in: result.repertoire.tree))
        #expect(gambit.comments == ["The gambit."])
        #expect(gambit.nags == [1])
        #expect(gambit.children.map(\.san) == ["e6", "c6", "dxc4"])
        #expect(RepertoireBuilderModel.importSummary(result) == "Imported 4 lines from 2 games, merged into one tree. 1 game starts from another position and was left out.")
        // What it writes, it reads back.
        let again = FixturePGN.read(result.repertoire.pgn)
        #expect(again.tree == result.repertoire.tree)
        await #expect(throws: FixtureData.refused("No game found in that PGN.")) {
            _ = try await api.importRepertoirePGN(id: id, pgn: "not a game", token: "t")
        }
        let seeded = try await api.seedRepertoire(id: id, token: "t")
        #expect(seeded.games == 30)
        #expect(seeded.repertoire.tree.map(\.san) == ["e4"])
    }

    /// The lines of a session replay with the app's own rules, and the
    /// trainer can run them: the wiring from the session to the grades.
    @Test @MainActor func aReviewRunsInTheLineTrainerAndItsGradesCount() async throws {
        let session = try await api.repertoireSession(id: id, mode: nil, token: "t")
        // Moves are due, so the server's choice is the review.
        #expect(session.mode == .review)
        #expect(session.deck == "repertoire:\(id)")
        #expect(session.chapterTitles == ["Italian Game"])
        for line in session.lines {
            var fen = line.startFen
            for step in line.steps {
                let before = try #require(Position(fen: step.fenBefore))
                let move = try #require(Move(uci: step.uci))
                #expect(step.fenBefore == fen)
                #expect(before.san(for: move) == step.san)
                #expect(before.playing(move)?.fen == step.fenAfter)
                #expect(step.mine == (before.turn == session.side))
                #expect(step.key == "\(before.positionKey)|\(step.uci)")
                fen = step.fenAfter
            }
        }
        let items = RepertoireTrainingModel.items(of: session)
        let item = try #require(items.first)
        let test = try #require(item.review)
        #expect(test.count == 3)

        let trainer = LineTrainerModel(line: item.line, side: session.side, review: test)
        trainer.timing = .immediate
        var graded: [MoveGrade]?
        trainer.onFinished = { graded = $0 }
        trainer.start()
        while graded == nil {
            await eventually { trainer.isOurTurn || graded != nil }
            guard graded == nil, let step = trainer.currentStep else { break }
            #expect(trainer.play(try #require(Move(uci: step.uci))))
        }
        let grades = try #require(graded)
        #expect(grades.count == 3)
        #expect(grades.allSatisfy { $0.grade == .good })

        try await api.sendGrades(deck: session.deck, grades: grades, token: "t")
        let after = try await api.repertoires(token: "t")
        #expect(after.totalDue == 0)
        // Nothing due any more: the server now chooses Learn, three new lines a day.
        let next = try await api.repertoireSession(id: id, mode: nil, token: "t")
        #expect(next.mode == .learn)
        #expect(next.learn.count == 3)
        #expect(RepertoireTrainingModel.items(of: next).allSatisfy { $0.review == nil })
    }

    @Test func aPositionSaysWhatIsPlayedAndWhatIsNotAnswered() async throws {
        let position = try await api.repertoirePosition(id: id, path: uci("e4 e5 Nf3"), ratings: "1400", token: "t")
        #expect(position.san == ["e4", "e5", "Nf3"])
        #expect(position.opponentToMove)
        #expect(position.inRepertoire)
        #expect(Set(position.covered) == Set(["b8c6", "d7d6"]))
        #expect(position.ratings == "1400")
        #expect(position.ratingBands.count == 9)
        #expect(position.gaps.map(\.san) == ["Nf6"])
        #expect(position.advice.kind == "keep")
        #expect(position.advice.moveNumber == 2)
        // The player's own games from here, with the repertoire's colour.
        #expect(position.mine.map(\.san) == ["Nc6", "d6", "Nf6"])
        #expect(position.mine.first?.uci == "b8c6")
        let own = try await api.repertoirePosition(id: id, path: uci("e4"), ratings: nil, token: "t")
        #expect(own.opponentToMove)
        #expect(own.ratings == "1000")
        let outside = try await api.repertoirePosition(id: id, path: uci("d4 d5"), ratings: nil, token: "t")
        #expect(!outside.inRepertoire)
        #expect(outside.covered.isEmpty)
        await #expect(throws: APIError.self) {
            _ = try await api.repertoirePosition(id: id, path: ["e2e5"], ratings: nil, token: "t")
        }
    }

    @Test(.samplePlayer(premium: true)) func gamesAreCheckedAgainstTheRepertoire() async throws {
        let check = try await api.repertoireAdherence(id: id, token: "t")
        #expect(check.hasTree)
        #expect(check.games.count == 30)
        #expect(check.followed == check.games.count { $0.status == "followed" })
        #expect(check.deviated == 2)
        let left = try #require(check.games.first { $0.deviation?.played == "Bb5" }?.deviation)
        #expect(left.moveNumber == 3)
        #expect(left.expected == ["Bc4"])
    }

    /// Every invented game is a line the rules accept, written as ChessCore writes it.
    @Test func theSampleGamesAreLegal() {
        let games = FixtureData.games()
        #expect(games.count == 52)
        #expect(Set(games.map(\.summary.id)).count == 52)
        for game in games {
            #expect(game.line.count >= 4, "\(game.summary.id) has its opening moves")
            #expect(FixtureData.sanLine(game.line.joined(separator: " ")) == game.line)
            #expect(game.summary.userColor == (game.side == .white ? "white" : "black"))
        }
        // Newest first.
        #expect(games.map(\.summary.playedAt) == games.map(\.summary.playedAt).sorted(by: >))
    }
}

// MARK: The builder

@Suite @MainActor struct RepertoireBuilderModelTests {
    private func makeModel(
        _ lines: String..., editable: Bool = true, debounce: Duration = .zero, onUnauthorized: @escaping () -> Void = {}
    ) async -> (RepertoireBuilderModel, RepertoireServer) {
        var nodes: [RepertoireNode] = []
        for line in lines { nodes = RepertoireTree.adding(line: uci(line), to: nodes, startFen: Position.startFEN)?.tree ?? nodes }
        let server = RepertoireServer(detail(tree: nodes, editable: editable))
        let model = RepertoireBuilderModel(id: "rep1", api: server, token: "t", debounce: debounce, onUnauthorized: onUnauthorized)
        await model.load()
        await model.statsSettled()
        return (model, server)
    }

    private func move(_ uci: String) -> Move { Move(uci: uci) ?? Move(from: Square(index: 0), to: Square(index: 0)) }

    @Test func itOpensOnTheStartPositionWithItsNumbers() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3", "e4 c5")
        #expect(model.phase == .ready)
        #expect(model.path.isEmpty)
        #expect(model.position == .start)
        #expect(model.movableSide == .white)
        #expect(!model.isOpponentToMove)
        #expect(server.positionsAsked == [""])
        #expect(model.statsPhase == .loaded)
        #expect(model.moves.map(\.san) == ["e4"])
        #expect(model.moves.first?.inRepertoire == true)
        #expect(model.moves.first?.movesBelow == 3)
        #expect(model.line.map(\.node.san) == ["e4", "e5", "Nf3"])
        #expect(model.line.allSatisfy { $0.isAhead })
        #expect(model.ratingLabel == "1000–1200")
    }

    @Test func aMoveOfTheRepertoireIsWalkedIntoNotWritten() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3", "e4 c5")
        #expect(model.play(move("e2e4")))
        #expect(model.path == ["e2e4"])
        #expect(model.isOpponentToMove)
        model.play(uci: "c7c5")
        #expect(model.path == ["e2e4", "c7c5"])
        #expect(model.lastMove == (move("c7c5")))
        #expect(model.currentNode?.san == "c5")
        model.goBack()
        model.goForward()
        #expect(model.path == uci("e4 e5"))
        model.goToStart()
        #expect(model.path.isEmpty)
        #expect(!model.canGoBack)
        #expect(server.log.allSatisfy { !$0.hasPrefix("add") })
        // An illegal move is not played at all.
        #expect(!model.play(move("e2e5")))
    }

    @Test func playingANewMoveAddsItFromTheStartAndStandsOnIt() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3")
        model.goTo(uci("e4 e5 Nf3"))
        await model.add("b8c6")
        #expect(server.log.contains("add e2e4,e7e5,g1f3,b8c6"))
        #expect(model.path == uci("e4 e5 Nf3 Nc6"))
        #expect(model.currentNode?.san == "Nc6")
        #expect(model.pending == nil)
        #expect(!model.isWriting)
        #expect(model.detail?.moves == 4)
        await model.statsSettled()
        #expect(server.positionsAsked.last == "e2e4,e7e5,g1f3,b8c6")
        #expect(model.statsPhase == .loaded)
    }

    /// The board shows the move at once; the server confirms it afterwards.
    @Test func aMovePlayedOnTheBoardShowsWhileItIsSent() async throws {
        let (model, server) = await makeModel("e4")
        #expect(model.play(move("d2d4")))
        #expect(model.pending?.san == "d4")
        #expect(model.shownPath == ["d2d4"])
        #expect(model.position.fen == "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1")
        // Nothing else is played until the server has answered.
        #expect(model.movableSide == nil)
        #expect(!model.play(move("e2e4")))
        await eventually { !model.isWriting && model.pending == nil }
        #expect(model.movableSide == .black)
        #expect(server.log.count { $0.hasPrefix("add") } == 1)
        #expect(model.path == ["d2d4"])
        #expect(server.log.contains("add d2d4"))
        #expect(model.position.fen == "rnbqkbnr/pppppppp/8/8/3P4/8/PPP1PPPP/RNBQKBNR b KQkq - 0 1")
    }

    @Test func aWholeLineIsAddedInOneWrite() async throws {
        let (model, server) = await makeModel("e4 e5")
        await model.add(line: uci("d4 d5 c4 e6"))
        #expect(server.log.filter { $0.hasPrefix("add") } == ["add d2d4,d7d5,c2c4,e7e6"])
        #expect(model.path == uci("d4 d5 c4 e6"))
        #expect(model.detail?.lines == 2)
    }

    @Test func removingAMoveTakesWhatFollowsAndStepsBack() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3 Nc6", "e4 c5")
        model.goTo(uci("e4 e5"))
        await model.removeCurrentMove()
        #expect(server.log.contains("remove e2e4,e7e5"))
        #expect(model.path == uci("e4"))
        #expect(model.detail?.moves == 2)
        #expect(model.moves.map(\.san) == ["c5"])
        // At the start there is nothing to remove.
        model.goToStart()
        await model.removeCurrentMove()
        #expect(server.log.count { $0.hasPrefix("remove") } == 1)
    }

    @Test func aNoteAndAGlyphGoToTheCurrentMove() async throws {
        let (model, server) = await makeModel("e4 e5")
        model.goTo(uci("e4"))
        await model.annotate(comment: "Best by test.", glyph: .set(1))
        #expect(server.log.contains("annotate e2e4 [Best by test.] set(1)"))
        #expect(model.currentNode?.comments == ["Best by test."])
        #expect(model.currentNode?.nags == [1])
        #expect(model.moves.isEmpty == false)
        // Before the first move there is a note, never a glyph.
        model.goToStart()
        await model.annotate(comment: "My plan.", glyph: .set(3))
        #expect(server.log.contains("annotate  [My plan.] keep"))
        #expect(model.path.isEmpty)
    }

    /// A rule of the server says no, here a write that lost against another
    /// device: its sentence is shown and the repertoire is read again.
    @Test func aRefusedWriteShowsItsMessageAndReadsAgain() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3")
        model.goTo(uci("e4 e5 Nf3"))
        let readsBefore = server.reads
        let message = "The repertoire was changed at the same time. Try again."
        // Meanwhile the other device removed 2. Nf3 and added the Sicilian.
        server.refuseNextWrite(
            .server(status: 422, code: "request_failed", message: message), treeBecomes: tree("e4 e5", "e4 c5")
        )
        await model.add("b8c6")
        #expect(model.notice == .init(text: message, isError: true))
        #expect(server.reads == readsBefore + 1)
        #expect(model.detail?.lines == 2)
        // The move the player stood on is gone: they stand where the tree still goes.
        #expect(model.path == uci("e4 e5"))
        #expect(model.pending == nil)
        #expect(!model.isWriting)
        #expect(!model.showsPremium)
        // The numbers are asked again for the position now shown.
        await model.statsSettled()
        #expect(server.positionsAsked.last == "e2e4,e7e5")
        // And the next write goes through.
        await model.add("g1f3")
        #expect(model.path == uci("e4 e5 Nf3"))
        #expect(model.notice == nil)
    }

    @Test func thePaywallOpensPremiumAndLeavesTheTreeAlone() async throws {
        let (model, server) = await makeModel("e4 e5")
        model.goTo(uci("e4 e5"))
        let reads = server.reads
        server.refuseNextWrite(FixtureData.freeLimit)
        await model.add("g1f3")
        #expect(model.showsPremium)
        #expect(model.notice?.isError == true)
        #expect(model.notice?.text.contains("20 lines") == true)
        #expect(model.path == uci("e4 e5"))
        #expect(model.pending == nil)
        #expect(model.detail?.moves == 2)
        // The paywall is not a reason to read the repertoire again.
        #expect(server.reads == reads)
    }

    @Test func aRevokedSessionIsReported() async throws {
        var expired = 0
        let (model, server) = await makeModel("e4", onUnauthorized: { expired += 1 })
        server.refuseNextWrite(.server(status: 401, code: "unauthorized", message: "Sign in to continue."))
        model.goTo(uci("e4"))
        await model.add("e7e5")
        #expect(expired == 1)
        #expect(model.notice == nil)
        #expect(!model.showsPremium)
    }

    @Test func beingOfflineKeepsThePlaceAndSaysSo() async throws {
        let (model, server) = await makeModel("e4 e5")
        model.goTo(uci("e4 e5"))
        let reads = server.reads
        server.refuseNextWrite(.offline)
        await model.add("g1f3")
        #expect(model.notice == .init(text: APIError.offline.message, isError: true))
        #expect(model.path == uci("e4 e5"))
        #expect(server.reads == reads)
    }

    /// Walking a line quickly asks for one position, the last: the server
    /// allows 60 a minute.
    @Test func statisticsWaitUntilThePlayerStops() async throws {
        let (model, server) = await makeModel("e4 e5 Nf3 Nc6 Bc4 Bc5 c3", debounce: .milliseconds(120))
        #expect(server.positionsAsked == [""])
        for _ in 0..<6 { model.goForward() }
        #expect(model.path == uci("e4 e5 Nf3 Nc6 Bc4 Bc5"))
        #expect(model.statsPhase == .loading)
        #expect(model.stats == nil)
        await model.statsSettled()
        #expect(server.positionsAsked == ["", "e2e4,e7e5,g1f3,b8c6,f1c4,f8c5"])
        #expect(model.statsPhase == .loaded)
        #expect(model.stats?.path == uci("e4 e5 Nf3 Nc6 Bc4 Bc5"))
        // A position already seen is not asked for again.
        model.goToStart()
        #expect(model.statsPhase == .loaded)
        await model.statsSettled()
        model.goTo(uci("e4 e5 Nf3 Nc6 Bc4 Bc5"))
        await model.statsSettled()
        #expect(server.positionsAsked.count == 2)
        // Another rating band is another question.
        model.choose(ratings: "1400")
        await model.statsSettled()
        #expect(server.positionsAsked.count == 3)
        #expect(model.ratingLabel == "1400–1600")
    }

    @Test func aChangeForgetsTheNumbersItMadeStale() async throws {
        let (model, server) = await makeModel("e4 e5")
        model.goTo(uci("e4"))
        await model.statsSettled()
        #expect(server.positionsAsked == ["", "e2e4"])
        // A new reply at 1. e4: what the repertoire holds there has changed.
        await model.add("c7c5")
        await model.statsSettled()
        model.goBack()
        await model.statsSettled()
        #expect(server.positionsAsked == ["", "e2e4", "e2e4,c7c5", "e2e4"])
        // The start position did not change: its numbers are still known.
        model.goToStart()
        await model.statsSettled()
        #expect(server.positionsAsked.count == 4)
    }

    @Test func tooManyPositionsSaysSoAndCanBeTriedAgain() async throws {
        let (model, server) = await makeModel("e4 e5")
        server.failPositions(.server(status: 429, code: "rate_limited", message: "Too many attempts. Try again in a moment."))
        model.goTo(uci("e4"))
        await model.statsSettled()
        #expect(model.statsPhase == .failed("Too many positions in a minute. The numbers are back in a moment."))
        // The repertoire's own moves are still there to walk.
        #expect(model.moves.map(\.san) == ["e5"])
        server.failPositions(nil)
        model.retryStats()
        await model.statsSettled()
        #expect(model.statsPhase == .loaded)
    }

    @Test func aRepertoireKeptForReadingIsWalkedNotChanged() async throws {
        let (model, server) = await makeModel("e4 e5", editable: false)
        #expect(!model.isEditable)
        #expect(model.play(move("e2e4")))
        #expect(model.path == ["e2e4"])
        #expect(!model.play(move("c7c5")))
        #expect(model.notice != nil)
        #expect(server.log.allSatisfy { !$0.hasPrefix("add") })
    }

    @Test func importingAndSeedingReplaceTheTreeAndSayWhatCameIn() async throws {
        let (model, server) = await makeModel("e4 e5")
        model.goTo(uci("e4 e5"))
        #expect(await model.importPGN("1. d4 d5 2. c4 (2. Bf4) e6"))
        #expect(model.path.isEmpty)
        #expect(model.detail?.lines == 2)
        #expect(model.notice == .init(text: "Imported 2 lines."))
        #expect(await model.seedFromGames())
        #expect(model.notice == .init(text: "Built from 12 games of yours."))
        #expect(model.tree.first?.san == "d4")
        server.refuseNextWrite(.server(status: 422, code: "request_failed", message: "No game found in that PGN."))
        #expect(await model.importPGN("nothing") == false)
        #expect(model.notice == .init(text: "No game found in that PGN.", isError: true))
        #expect(await model.rename("  Queen's Gambit "))
        #expect(model.detail?.name == "Queen's Gambit")
    }

    /// The repertoire's own moves lead; then what is played, the replies
    /// without an answer flagged.
    @Test func theMovesOfAPositionAreOrderedForBuilding() async throws {
        let (model, server) = await makeModel("e4 e5", "e4 c5")
        server.leaveUnanswered(["e7e6", "c7c6"], at: ["e2e4"])
        model.goTo(["e2e4"])
        await model.statsSettled()
        let moves = model.moves
        #expect(moves.map(\.id) == ["e7e5", "c7c5", "e7e6", "c7c6"])
        #expect(moves.map(\.inRepertoire) == [true, true, false, false])
        #expect(moves.map(\.isUnanswered) == [false, false, true, true])
        #expect(model.unanswered == 2)
        #expect(moves[0].stat?.frequency == 0.5)
        #expect(moves[0].stat?.isMine == false)
        #expect((moves[0].stat?.first, moves[0].stat?.draws, moves[0].stat?.last) == (50, 10, 40))

        // The player's own games: results from their side, and a move the
        // server could not name is shown without being playable.
        let children = try #require(RepertoireTree.children(at: ["e2e4"], in: model.tree))
        let stats = try #require(model.stats)
        let own = RepertoirePosition(
            fen: stats.fen, path: stats.path, san: stats.san, inRepertoire: true, covered: stats.covered, masters: nil,
            lichess: nil, ratings: "1000", ratingBands: [], mine: [
                .init(san: "e5", uci: "e7e5", games: 8, freq: 0.8, score: 0.75, wins: 6, draws: 0, losses: 2),
                .init(san: "d5", uci: nil, games: 2, freq: 0.2, score: 0.5, wins: 1, draws: 0, losses: 1),
            ], opponentToMove: true, gaps: [], advice: stats.advice
        )
        let mine = RepertoireBuilderModel.moves(children: children, stats: own, source: .mine)
        #expect(mine.map(\.san) == ["e5", "c5", "d5"])
        #expect(mine[0].stat?.isMine == true)
        #expect(mine[0].stat?.first == 6)
        #expect(mine[1].stat == nil)
        #expect(mine[2].uci == nil)
        // Without Lichess the players' numbers are the masters'.
        let masters = RepertoireBuilderModel.moves(
            children: [], stats: RepertoirePosition(
                fen: stats.fen, path: [], san: [], inRepertoire: true, covered: [], masters: stats.masters, lichess: nil,
                ratings: "1000", ratingBands: [], mine: [], opponentToMove: false, gaps: [], advice: stats.advice
            ), source: .players
        )
        #expect(masters.count == 4)
        #expect(RepertoireBuilderModel.moves(children: children, stats: nil, source: .players).map(\.san) == ["e5", "c5"])
    }

    @Test func aRepertoireThatDoesNotLoadSaysWhy() async {
        final class Gone: RepertoiresAPI, @unchecked Sendable {
            func repertoire(id: String, token: String) async throws -> RepertoireDetail {
                throw APIError.server(status: 404, code: "not_found", message: "Repertoire not found.")
            }
        }
        let model = RepertoireBuilderModel(id: "gone", api: Gone(), token: "t")
        await model.load()
        #expect(model.phase == .failed("Repertoire not found."))
        #expect(model.movableSide == nil)
    }
}

// MARK: The list

@Suite(.samplePlayer()) @MainActor struct RepertoiresModelTests {
    @Test func theListFollowsTheSamplePlayer() async throws {
        let model = RepertoiresModel(api: FixtureAPI(delay: .zero), token: "t")
        await model.load()
        #expect(model.phase == .ready)
        let card = try #require(model.repertoires.first)
        #expect(model.top == card)
        #expect(card.status.text == "3 due")
        #expect(card.status.isDue)
        #expect(card.side == .white)
        #expect(abs(card.learnedShare - 2.0 / 6.0) < 0.001)

        // The free plan holds one: the paywall, and the form is told why.
        await #expect(throws: FixtureData.freeLimit) { _ = try await model.create(name: "Second", color: "BLACK") }
        #expect(model.showsPremium)

        await model.rename(card, to: "Giuoco Piano")
        #expect(model.repertoires.first?.name == "Giuoco Piano")
        #expect(model.notice == nil)
        await model.rename(card, to: "   ")
        #expect(model.notice == "Name cannot be empty.")

        await model.delete(card)
        #expect(model.repertoires.isEmpty)
        #expect(model.list?.canCreate == true)
        let created = try await model.create(name: "Caro-Kann", color: "BLACK")
        #expect(created.color == "BLACK")
        #expect(model.repertoires.map(\.name) == ["Caro-Kann"])
        #expect(model.repertoires.first?.status.text == "Up to date")
    }

    @Test func aRevokedSessionIsReported() async {
        final class Revoked: RepertoiresAPI, @unchecked Sendable {}
        var expired = 0
        let model = RepertoiresModel(api: Revoked(), token: "t", onUnauthorized: { expired += 1 })
        await model.load()
        #expect(expired == 1)
        #expect(model.phase == .failed("Not stubbed."))
    }
}

// MARK: Training

/// A value shared with the closures a model calls from elsewhere.
private nonisolated final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

@Suite @MainActor struct RepertoireTrainingTests {
    private func deck(_ id: String, kind: String, due: Int) -> DueSummary.Deck {
        DueSummary.Deck(
            deck: id, kind: kind, name: "Deck \(id)", color: "WHITE",
            progress: DeckProgress(lines: 6, learned: 2, newLines: 4, dueLines: due, solidLines: 0, dueMoves: due * 2, moves: 20)
        )
    }

    /// Today's due card: a repertoire deck opens its review.
    @Test func aDueRepertoireOpensItsReview() throws {
        let request = try #require(RepertoireTrainingRequest(deck: deck("repertoire:abc123", kind: "repertoire", due: 2)))
        #expect(request.id == "abc123")
        #expect(request.mode == .review)
        #expect(request.name == "Deck repertoire:abc123")
        #expect(RepertoireTrainingRequest(deck: deck("course:practical-caro-kann", kind: "course", due: 2)) == nil)
        #expect(RepertoireTrainingRequest(deck: deck("repertoire:", kind: "repertoire", due: 2)) == nil)

        let courses: CoursesResponse = try LiveAPI.decode(status: 200, data: FixtureAPI.data("courses"))
        let due = DueSummary(
            totalDue: 9,
            decks: [
                deck("repertoire:abc123", kind: "repertoire", due: 2),
                deck("course:practical-caro-kann", kind: "course", due: 1),
                deck("repertoire:quiet", kind: "repertoire", due: 0),
                deck("course:not-in-the-catalogue", kind: "course", due: 3),
            ],
            top: "repertoire:abc123", learnNext: nil
        )
        let rows = DueRow.rows(due: due, courses: courses.courses)
        #expect(rows.map(\.target) == [.repertoire(request), .course(slug: "practical-caro-kann")])
    }

    private func session(mode: SessionMode) throws -> CourseSession {
        // Two lines: the free line of two captured courses.
        let lines = try ["practical-caro-kann", "practical-london-system"].map { slug in
            let captured: CourseSession = try LiveAPI.decode(status: 200, data: FixtureAPI.data("session-learn-\(slug)"))
            return try #require(captured.lines.first)
        }
        return CourseSession(
            deck: "repertoire:rep1", mode: mode, color: "BLACK", lines: lines,
            learn: mode == .learn ? lines.reversed().map(\.id) + ["missing"] : [],
            review: mode == .review ? [.init(lineId: lines[1].id, test: [1, 3]), .init(lineId: "missing", test: [1])] : [],
            known: [], next: nil, chapterTitles: ["My Black"], narration: nil
        )
    }

    @Test func theSessionIsRunInTheOrderTheServerPlanned() async throws {
        let learn = try session(mode: .learn)
        let asked = Box<[String]>([])
        let model = RepertoireTrainingModel(
            request: .init(id: "rep1", name: "My Black"),
            loadSession: { id, mode in
                asked.value.append("\(id) \(mode?.rawValue ?? "server's choice")")
                return learn
            },
            sendGrades: { _, _ in }
        )
        #expect(model.phase == .loading)
        await model.load()
        #expect(asked.value == ["rep1 server's choice"])
        // The plan's order, not the order of the lines; an id without a line is skipped.
        #expect(model.items.map(\.id) == [learn.lines[1].id, learn.lines[0].id])
        #expect(model.items.allSatisfy { $0.review == nil })
        #expect(model.label == "New line 1 of 2")
        #expect(model.hasNext)
        model.advance()
        #expect(model.current?.id == learn.lines[0].id)
        #expect(!model.hasNext)
        model.advance()
        #expect(model.index == 1)

        let review = try session(mode: .review)
        let reviewing = RepertoireTrainingModel(
            request: .init(id: "rep1", name: "My Black", mode: .review),
            loadSession: { _, mode in
                asked.value.append(mode?.rawValue ?? "-")
                return review
            },
            sendGrades: { _, _ in }
        )
        await reviewing.load()
        #expect(asked.value.last == "review")
        #expect(reviewing.items.map(\.review) == [[1, 3]])
        #expect(reviewing.label == "Review · 1 of 1")
    }

    /// Grades go to the deck the session names; what the server missed goes
    /// out again with the next line's.
    @Test func gradesGoToTheDeckAndAreNotLostToAFailure() async throws {
        let learn = try session(mode: .learn)
        let sent = Box<[(deck: String, count: Int)]>([])
        let failure = Box<APIError?>(nil)
        var expired = 0
        let model = RepertoireTrainingModel(
            request: .init(id: "rep1", name: "My Black"),
            loadSession: { _, _ in learn },
            sendGrades: { deck, grades in
                if let error = failure.value { throw error }
                sent.value.append((deck, grades.count))
            },
            onUnauthorized: { expired += 1 }
        )
        let grade = MoveGrade(fen: Position.startFEN, uci: "e2e4", grade: .good)
        // Nothing is sent before a session is there, nor for an empty line.
        await model.report([grade])
        await model.load()
        await model.report([])
        #expect(sent.value.isEmpty)

        await model.report([grade, grade])
        #expect(sent.value.map(\.deck) == ["repertoire:rep1"])
        #expect(sent.value.map(\.count) == [2])

        failure.value = .offline
        await model.report([grade])
        #expect(model.unsent.count == 1)
        failure.value = nil
        await model.report([grade, grade])
        #expect(sent.value.map(\.count) == [2, 3])
        #expect(model.unsent.isEmpty)

        failure.value = .server(status: 401, code: "unauthorized", message: "Sign in to continue.")
        await model.report([grade])
        #expect(expired == 1)
        #expect(model.unsent.isEmpty)
    }

    @Test func aRepertoireTheFreePlanDoesNotTrainIsThePaywall() async {
        let message = "Free includes training your first repertoire. Premium trains them all."
        let model = RepertoireTrainingModel(
            request: .init(id: "second", name: "Second"),
            loadSession: { _, _ in throw APIError.server(status: 403, code: "premium_required", message: message) },
            sendGrades: { _, _ in }
        )
        await model.load()
        #expect(model.phase == .premiumRequired(message))
        #expect(model.items.isEmpty)
        #expect(model.current == nil)

        let offline = RepertoireTrainingModel(
            request: .init(id: "rep1", name: "First"),
            loadSession: { _, _ in throw APIError.offline },
            sendGrades: { _, _ in }
        )
        await offline.load()
        #expect(offline.phase == .failed(APIError.offline.message))
    }
}
