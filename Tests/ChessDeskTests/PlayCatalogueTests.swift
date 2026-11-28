import Foundation
import Testing
@testable import ChessDesk

// The catalogue of bots: `Fixtures/api-v1/play-bots.json` is the answer of
// production to `GET /api/v1/play/bots`, captured by
// `scripts/sync-play-bots.sh`. The models read it whole.

/// Stubs of the other features need not know about the bots.
nonisolated extension ChessDeskAPI {
    var savesBotGames: Bool { false }
    func playBots(token: String?) async throws -> PlayCatalogue { try FixtureAPI.playCatalogue() }
    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> GameDetail {
        throw APIError.server(status: 401, code: "unauthorized", message: "Not stubbed.")
    }
}

/// Answers one canned response and remembers the request it was asked.
nonisolated private final class PlayTransport: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answer: (status: Int, body: Data) = (200, Data())
    nonisolated(unsafe) static var requests: [(request: URLRequest, body: Data?)] = []

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlayTransport.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        Self.requests.append((request, body))
        let response = HTTPURLResponse(
            url: request.url.unsafelyUnwrapped, statusCode: Self.answer.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        ).unsafelyUnwrapped
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// The expectations of the site's `authed-bots.test.ts`, on what production answers.
@Suite struct PlayCatalogueTests {
    private let catalogue: PlayCatalogue

    init() throws {
        catalogue = try FixtureAPI.playCatalogue()
    }

    @Test func holdsTheWholeRosterWeakestFirst() {
        #expect(catalogue.bots.count == 41)
        #expect(Set(catalogue.bots.map(\.id)).count == 41)
        #expect(zip(catalogue.bots, catalogue.bots.dropFirst()).allSatisfy { $0.rating < $1.rating })
        #expect(catalogue.bots.allSatisfy { (400...2500).contains($0.rating) })
        #expect(catalogue.bots.first?.id == "peru")
        #expect(catalogue.bots.last?.id == "germany")
        #expect(catalogue.bots.allSatisfy { !$0.name.isEmpty && !$0.country.isEmpty && !$0.tagline.isEmpty })
    }

    @Test func tiersAreTheServers() {
        #expect(catalogue.tiers.map(\.id) == ["beginner", "club", "advanced", "expert"])
        #expect(catalogue.tiers.allSatisfy { !$0.label.isEmpty && !$0.blurb.isEmpty })
        // Every bot sits in a tier the catalogue lists; the app computes none.
        let tiers = Set(catalogue.tiers.map(\.id))
        #expect(catalogue.bots.allSatisfy { tiers.contains($0.tier) })
        #expect(catalogue.tiers.map { catalogue.bots(in: $0).count } == [10, 10, 10, 11])
        #expect(catalogue.bots(in: catalogue.tiers[1]).first?.name == "Jack")
    }

    @Test func artAndFlavourAreTheServers() {
        let byID = Dictionary(uniqueKeysWithValues: catalogue.bots.map { ($0.id, $0) })
        #expect(byID["france"]?.portraitUrl == "https://chessdesk.app/bots/french.webp")
        #expect(byID["peru"]?.portraitUrl == "https://chessdesk.app/bots/peru.webp")
        #expect(byID["peru"]?.flagUrl == "https://chessdesk.app/flags/peru.svg")
        #expect(byID["france"]?.name == "Étienne")
        // Every portrait and flag is a full URL the app can fetch as it is.
        for bot in catalogue.bots {
            #expect(PlayAssets.url(bot.portraitUrl)?.scheme == "https", "\(bot.id)")
            #expect(URL(string: bot.flagUrl)?.pathExtension == "svg", "\(bot.id)")
        }
        let openers: Set<String> = ["e2e4", "d2d4", "c2c4", "g1f3"]
        #expect(catalogue.bots.allSatisfy { $0.firstMove.map(openers.contains) == true })
        #expect(catalogue.bots.allSatisfy { (0...1).contains($0.wildness) })
        // Everything is free on the site today: no gate is invented here.
        #expect(catalogue.bots.allSatisfy { $0.access == .free })
        #expect(catalogue.custom.access == .free)
    }

    /// What moves each bot is stated by the server, bot by bot.
    @Test func everyBotStatesItsEngineParameters() throws {
        let stockfish = catalogue.engines.stockfish
        for bot in catalogue.bots {
            #expect(bot.temperature > 0 && bot.temperature <= 10, "\(bot.id)")
            #expect((stockfish.minElo...stockfish.maxElo).contains(bot.stockfishElo), "\(bot.id)")
        }
        let peru = try #require(catalogue.bots.first)
        #expect(peru.rating == 408)
        #expect(peru.temperature == 1.35)
        #expect(peru.stockfishElo == 1320)
        let germany = try #require(catalogue.bots.last)
        #expect(germany.temperature == 0.64)
        #expect(germany.stockfishElo == 2401)
        // Wilder bots sample more loosely.
        #expect(germany.temperature < peru.temperature)
    }

    @Test func theBuiltOpponentAndTheEngines() {
        #expect(catalogue.custom.id == "custom")
        #expect(catalogue.custom.name == "Custom bot")
        #expect(catalogue.custom.rating == .init(min: 400, max: 2400, step: 10, default: 1500))
        #expect(catalogue.custom.temperature == 0.9)

        let engines = catalogue.engines
        #expect(engines.order == ["maia-3", "stockfish"])
        #expect(engines.moveTimeoutMs == 12000)
        #expect(engines.maia.model == "maia3-5m")
        #expect(engines.maia.modelUrl.absoluteString.hasSuffix("/maia3-5m.onnx"))
        #expect(engines.maia.modelUrl.scheme == "https")
        #expect(engines.maia.policyOutput == "logits_move")
        #expect(engines.maia.sampling == .init(topP: 0.9, defaultTemperature: 1))
        #expect(engines.maia.eloMax == 5000)
        #expect(engines.maia.initBudgetMs == 20000)
        #expect(engines.maia.warmupBudgetMs == 1500)
        #expect(engines.stockfish == StockfishEngineInfo(minElo: 1320, maxElo: 3190, moveTimeMs: 300))
        // Captured without a session: a visitor saves nothing.
        #expect(!catalogue.canSaveGames)
    }

    @Test func gatesAreReadFromTheTwoFlags() throws {
        #expect(BotAccess(requiresAccount: false, requiresPremium: false) == .free)
        #expect(BotAccess(requiresAccount: true, requiresPremium: false) == .account)
        #expect(BotAccess(requiresAccount: false, requiresPremium: true) == .premium)
        #expect(BotAccess(requiresAccount: true, requiresPremium: true) == .premium)
        // A bot the server gates decodes as gated, and fields added later are ignored.
        var object = try #require(JSONSerialization.jsonObject(with: FixtureAPI.data("play-bots")) as? [String: Any])
        var bots = try #require(object["bots"] as? [[String: Any]])
        bots[0]["requiresPremium"] = true
        bots[0]["somethingNew"] = 1
        bots[1]["requiresAccount"] = true
        bots[2]["firstMove"] = NSNull()
        object["bots"] = bots
        let decoded: PlayCatalogue = try LiveAPI.decode(status: 200, data: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.bots.prefix(3).map(\.access) == [.premium, .account, .free])
        #expect(decoded.bots[2].firstMove == nil)
    }

    @Test func sampleDataServesTheCapturedCatalogueAndSavesNothing() async throws {
        let sample = FixtureAPI(delay: .zero)
        #expect(try await sample.playBots(token: nil) == catalogue)
        #expect(!sample.savesBotGames)
    }
}

/// The live client on the two routes of the feature, against a canned server.
/// Serialized: the canned answer is shared.
@Suite(.serialized) struct PlayLiveClientTests {
    private func client() throws -> LiveAPI {
        PlayTransport.requests = []
        var api = LiveAPI(baseURL: try #require(URL(string: "https://chessdesk.app")))
        api.session = PlayTransport.session()
        return api
    }

    @Test func theCatalogueIsReadFromTheServerWithOrWithoutASession() async throws {
        let api = try client()
        #expect(api.savesBotGames)
        PlayTransport.answer = (200, try FixtureAPI.data("play-bots"))
        let guest = try await api.playBots(token: nil)
        #expect(guest == (try FixtureAPI.playCatalogue()))
        _ = try await api.playBots(token: "abc")
        let sent = PlayTransport.requests.map(\.request)
        #expect(sent.map(\.httpMethod) == ["GET", "GET"])
        #expect(sent.map(\.url?.absoluteString) == Array(repeating: "https://chessdesk.app/api/v1/play/bots", count: 2))
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer abc")
    }

    @Test func aGameIsPostedAndTheSavedGameComesBack() async throws {
        let api = try client()
        PlayTransport.answer = (200, Data("""
        {"id":"g_123","source":"BOT","white":"Ana Silva","black":"Maria","whiteElo":null,"blackElo":446,
         "result":"1-0","timeClass":"casual","opening":null,"userColor":"white","playedAt":"2026-11-28T04:14:12.000Z",
         "ply":7,"starred":false,"reviewed":false,"pgn":"1. e4 e5 1-0","url":null,"review":null}
        """.utf8))
        let request = SaveBotGameRequest(bot: "philippines", rating: nil, userColor: "white", result: "1-0", engine: "maia-3", pgn: "1. e4 e5 1-0")
        let saved = try await api.saveBotGame(request, token: "abc")
        // Its id is the one the review screen opens.
        #expect(saved.id == "g_123")
        #expect(saved.source == "BOT")
        let sent = try #require(PlayTransport.requests.first)
        #expect(sent.request.httpMethod == "POST")
        #expect(sent.request.url?.absoluteString == "https://chessdesk.app/api/v1/play/games")
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(sent.request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let posted = try #require(sent.body)
        let body = try #require(JSONSerialization.jsonObject(with: posted) as? [String: Any])
        #expect(body as NSDictionary == ["bot": "philippines", "userColor": "white", "result": "1-0", "engine": "maia-3", "pgn": "1. e4 e5 1-0"])
    }

    @Test func whatTheServerRefusesIsSaidInItsWords() async throws {
        let api = try client()
        PlayTransport.answer = (400, Data(#"{"error":{"code":"invalid_request","message":"Unknown bot, or a rating outside the range of the custom bot."}}"#.utf8))
        let request = SaveBotGameRequest(bot: "nobody", rating: nil, userColor: "white", result: "1-0", engine: "maia-3", pgn: "1. e4")
        await #expect(throws: APIError.server(status: 400, code: "invalid_request", message: "Unknown bot, or a rating outside the range of the custom bot.")) {
            _ = try await api.saveBotGame(request, token: "abc")
        }
        PlayTransport.answer = (401, Data(#"{"error":{"code":"unauthorized","message":"Sign in to continue."}}"#.utf8))
        await #expect(throws: APIError.self) { _ = try await api.saveBotGame(request, token: "expired") }
    }
}
