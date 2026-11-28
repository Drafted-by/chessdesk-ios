import ChessCore
import Foundation
import Testing
@testable import ChessDesk

nonisolated private let detailedSlugs = ["practical-caro-kann", "aggressive-1e4", "practical-london-system"]

private func fixture<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) throws -> Value {
    try LiveAPI.decode(status: 200, data: FixtureAPI.data(name))
}

/// The captured answers of the site decode into the app's models.
@Suite struct FixtureDecodingTests {
    @Test func catalogue() throws {
        let response: CoursesResponse = try fixture("courses")
        #expect(response.courses.count == 31)
        let slugs = Set(response.courses.map(\.slug))
        #expect(slugs.count == response.courses.count)
        for slug in detailedSlugs { #expect(slugs.contains(slug)) }
        for course in response.courses {
            #expect(Position(fen: course.previewFen) != nil, "\(course.slug) preview position")
            #expect(course.previewMove == nil || course.previewHighlight != nil, "\(course.slug) preview move")
        }
    }

    @Test(arguments: detailedSlugs)
    func courseDetail(slug: String) throws {
        let course: CourseDetail = try fixture("course-\(slug)")
        #expect(course.slug == slug)
        #expect(course.chapters.count == course.totals.chapters)
        #expect(course.chapters.flatMap(\.lines).count == course.totals.lines)
        let free = course.chapters.flatMap(\.lines).filter(\.free)
        #expect(free.map(\.id) == [course.freeLineId])
    }

    @Test func errorShape() throws {
        let body = Data(#"{"error":{"code":"premium_required","message":"This line is part of Premium."}}"#.utf8)
        #expect(throws: APIError.server(status: 403, code: "premium_required", message: "This line is part of Premium.")) {
            let _: CourseSession = try LiveAPI.decode(status: 403, data: body)
        }
        #expect(throws: APIError.unreadable) {
            let _: CourseSession = try LiveAPI.decode(status: 502, data: Data("<html>".utf8))
        }
    }

    @Test func datesWithMilliseconds() {
        #expect(APICoding.parseDate("2027-01-25T16:29:15.210Z") != nil)
        #expect(APICoding.parseDate("2027-01-25T16:29:15Z") != nil)
        #expect(APICoding.parseDate("tomorrow") == nil)
    }
}

/// Every move the server sends is legal for the app's own rules, and both
/// agree on the resulting position and on the notation.
@Suite struct LineReplayTests {
    @Test(arguments: detailedSlugs)
    func serverLinesReplayWithChessCore(slug: String) throws {
        let session: CourseSession = try fixture("session-learn-\(slug)")
        #expect(!session.lines.isEmpty)
        for line in session.lines {
            var expectedFEN = line.startFen
            for step in line.steps {
                #expect(step.fenBefore == expectedFEN, "\(slug) \(line.id) ply \(step.ply) starts where the last ended")
                let before = try #require(Position(fen: step.fenBefore))
                let move = try #require(Move(uci: step.uci))
                let after = try #require(before.playing(move), "\(slug) \(line.id): \(step.uci) is legal")
                let served = try #require(Position(fen: step.fenAfter))
                #expect(after.positionKey == served.positionKey, "\(slug) \(line.id) after \(step.san)")
                #expect(before.san(for: move) == step.san, "\(slug) \(line.id) SAN of \(step.uci)")
                #expect(step.mine == (before.turn == session.side))
                expectedFEN = step.fenAfter
            }
        }
    }

    /// The narration key must be the site's, or no clip is ever found.
    @Test(arguments: detailedSlugs)
    func narrationKeysMatchTheServer(slug: String) throws {
        let session: CourseSession = try fixture("session-learn-\(slug)")
        let narration = try #require(session.narration)
        let comments = session.lines.flatMap(\.steps).flatMap(\.comments)
        #expect(!comments.isEmpty)
        let voiced = comments.filter { NarrationKey.clipURL(for: $0, in: narration) != nil }
        #expect(voiced.count == comments.count, "\(voiced.count) of \(comments.count) notes have a clip")
    }

    @Test func narrationKeyIsFNV1a() {
        #expect(NarrationKey.make("") == "811c9dc5")
        #expect(NarrationKey.make("a") == "e40c292c")
        #expect(NarrationKey.make("foobar") == "bf9cf968")
    }
}

/// The models against the site's OpenAPI contract: for every schema the app
/// reads, an example built from the contract's *required* fields only must
/// decode. A field the app treats as always present but the contract marks
/// optional fails here.
@Suite struct ContractTests {
    private static func contract() throws -> [String: Any] {
        let bundle = Bundle(for: ContractBundleToken.self)
        let url = try #require(bundle.url(forResource: "openapi-v1", withExtension: "json", subdirectory: "contracts"))
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        return try #require(object as? [String: Any])
    }

    private static func example(_ schema: [String: Any], _ schemas: [String: Any]) -> Any {
        if let reference = schema["$ref"] as? String, let name = reference.split(separator: "/").last,
           let target = schemas[String(name)] as? [String: Any] {
            return example(target, schemas)
        }
        if let options = schema["anyOf"] as? [[String: Any]] {
            let chosen = options.first { ($0["type"] as? String) != "null" } ?? options[0]
            return example(chosen, schemas)
        }
        if let values = schema["enum"] as? [Any], let first = values.first { return first }
        if let constant = schema["const"] { return constant }
        let type = (schema["type"] as? String) ?? (schema["type"] as? [String])?.first { $0 != "null" } ?? "object"
        switch type {
        case "string":
            return (schema["format"] as? String) == "date-time" ? "2027-01-25T16:29:15.210Z" : "text"
        case "integer", "number": return 1
        case "boolean": return true
        case "array":
            let items = schema["items"] as? [String: Any] ?? [:]
            return [example(items, schemas)]
        default:
            let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
            let required = schema["required"] as? [String] ?? []
            var object: [String: Any] = [:]
            for name in required { object[name] = properties[name].map { example($0, schemas) } }
            return object
        }
    }

    private func decodeExample<Value: Decodable>(_ name: String, as type: Value.Type) throws {
        let contract = try Self.contract()
        let components = try #require(contract["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        let schema = try #require(schemas[name] as? [String: Any], "schema \(name) is in the contract")
        var example = Self.example(schema, schemas)
        // Dates are plain strings in the contract; give the known ones a date.
        if var object = example as? [String: Any], object["expiresAt"] != nil {
            object["expiresAt"] = "2027-01-25T16:29:15.210Z"
            example = object
        }
        let data = try JSONSerialization.data(withJSONObject: example)
        do {
            _ = try APICoding.decoder.decode(Value.self, from: data)
        } catch {
            Issue.record("\(name) no longer decodes from its contract example: \(error)")
        }
    }

    @Test func modelsDecodeContractExamples() throws {
        try decodeExample("AuthSession", as: AuthSession.self)
        try decodeExample("Me", as: Me.self)
        try decodeExample("Courses", as: CoursesResponse.self)
        try decodeExample("CourseDetail", as: CourseDetail.self)
        try decodeExample("CourseSession", as: CourseSession.self)
        try decodeExample("DueSummary", as: DueSummary.self)
        try decodeExample("LocalProgress", as: LocalProgressResult.self)
        try decodeExample("ApiError", as: APIErrorBody.self)
        try decodeExample("LinkedAccounts", as: LinkedAccountsResponse.self)
        try decodeExample("ImportChunk", as: ImportChunk.self)
        try decodeExample("GamesPage", as: GamesPage.self)
        try decodeExample("GameDetail", as: GameDetail.self)
        try decodeExample("MistakeQueue", as: MistakeQueue.self)
        try decodeExample("MistakeAttempt", as: MistakeAttempt.self)
        try decodeExample("PuzzleOverview", as: PuzzleOverview.self)
        try decodeExample("FreePuzzles", as: FreePuzzles.self)
        try decodeExample("Puzzle", as: Puzzle.self)
        try decodeExample("PuzzleAttempt", as: PuzzleAttempt.self)
        try decodeExample("WoodpeckerOverview", as: WoodpeckerOverview.self)
        try decodeExample("WoodpeckerRun", as: WoodpeckerRun.self)
        try decodeExample("WoodpeckerStep", as: WoodpeckerStep.self)
        try decodeExample("WoodpeckerReport", as: WoodpeckerReport.self)
    }

    @Test func contractServesEveryRouteTheAppCalls() throws {
        let contract = try Self.contract()
        let paths = try #require(contract["paths"] as? [String: Any])
        let used = [
            "/api/v1/auth/login", "/api/v1/auth/refresh", "/api/v1/me",
            "/api/v1/auth/signup", "/api/v1/auth/apple", "/api/v1/auth/verification",
            "/api/v1/purchases/apple",
            "/api/v1/accounts", "/api/v1/accounts/{provider}", "/api/v1/accounts/{provider}/import",
            "/api/v1/games", "/api/v1/games/{gameId}", "/api/v1/games/{gameId}/star", "/api/v1/games/{gameId}/review",
            "/api/v1/mistakes", "/api/v1/mistakes/{mistakeId}/attempts",
            "/api/v1/courses", "/api/v1/courses/{slug}", "/api/v1/courses/{slug}/session",
            "/api/v1/courses/{slug}/enrollment", "/api/v1/courses/{slug}/local-progress",
            "/api/v1/training/grades", "/api/v1/training/due",
            "/api/v1/puzzles", "/api/v1/puzzles/free", "/api/v1/puzzles/next", "/api/v1/puzzles/{puzzleId}/attempts",
            "/api/v1/woodpecker", "/api/v1/woodpecker/set", "/api/v1/woodpecker/set/solves",
            "/api/v1/woodpecker/set/cycles", "/api/v1/woodpecker/set/puzzles/{puzzleId}", "/api/v1/woodpecker/report",
        ]
        for path in used { #expect(paths[path] != nil, "\(path) is in the contract") }
    }

    /// The request bodies the app sends hold every field the contract requires.
    @Test func accountRequestsCarryWhatTheContractRequires() throws {
        let contract = try Self.contract()
        let components = try #require(contract["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        func keys(_ body: some Encodable) throws -> Set<String> {
            let object = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(body))
            return Set(try #require(object as? [String: Any]).keys)
        }
        func required(_ name: String) throws -> Set<String> {
            let schema = try #require(schemas[name] as? [String: Any], "schema \(name) is in the contract")
            return Set(schema["required"] as? [String] ?? [])
        }
        let signup = SignupRequest(firstName: "Ana", lastName: "Silva", email: "ana@example.com", password: "longenough")
        #expect(try keys(signup) == required("SignupRequest"))
        let apple = AppleSignInRequest(identityToken: "jwt", firstName: nil, lastName: nil)
        #expect(try required("AppleSignInRequest").isSubset(of: keys(apple)))
        // Nothing is required to delete a passwordless account.
        #expect(try required("DeleteAccountRequest").isEmpty)
        let paths = try #require(contract["paths"] as? [String: Any])
        let me = try #require(paths["/api/v1/me"] as? [String: Any])
        #expect(me["delete"] != nil, "DELETE /api/v1/me is in the contract")
    }

    /// The puzzle and Woodpecker bodies carry what the contract requires.
    @Test func puzzleRequestsCarryWhatTheContractRequires() throws {
        let contract = try Self.contract()
        let components = try #require(contract["components"] as? [String: Any])
        let schemas = try #require(components["schemas"] as? [String: Any])
        func check(_ body: some Encodable, _ name: String) throws {
            let object = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(body))
            let keys = Set(try #require(object as? [String: Any]).keys)
            let schema = try #require(schemas[name] as? [String: Any], "schema \(name) is in the contract")
            let required = Set(schema["required"] as? [String] ?? [])
            #expect(required.isSubset(of: keys), "\(name) carries \(required)")
        }
        try check(PuzzleAttemptRequest(solved: true, ms: 4200), "PuzzleAttemptRequest")
        try check(NextPuzzleRequest(theme: nil), "NextPuzzleRequest")
        try check(WoodpeckerSetRequest(size: nil, theme: nil), "WoodpeckerSetRequest")
        try check(WoodpeckerSetStatusRequest(status: .completed), "WoodpeckerSetStatusRequest")
        try check(WoodpeckerSolveRequest(puzzleId: "p1", correct: false, ms: 900), "WoodpeckerSolveRequest")
    }

    @Test func requestsAreBuiltAsTheContractSays() throws {
        let api = LiveAPI(baseURL: try #require(URL(string: "https://chessdesk.app")))
        let request = api.request(
            "GET", "courses/practical-caro-kann/session",
            query: [URLQueryItem(name: "mode", value: "learn"), URLQueryItem(name: "line", value: "0.0")],
            token: "abc"
        )
        #expect(request.url?.absoluteString == "https://chessdesk.app/api/v1/courses/practical-caro-kann/session?mode=learn&line=0.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        let guest = api.request("GET", "courses", query: [], token: nil)
        #expect(guest.value(forHTTPHeaderField: "Authorization") == nil)
    }
}

private final class ContractBundleToken {}
