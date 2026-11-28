import Foundation
import Testing
@testable import ChessDesk

// The catalogue of bots: the bundled mirror of the site's roster, and what
// the two clients answer until the endpoint is served.

/// Stubs of the other features need not know about the bots.
nonisolated extension ChessDeskAPI {
    var savesBotGames: Bool { false }
    func playBots(token: String?) async throws -> PlayCatalogue { try BundledPlayCatalogue.load() }
    func saveBotGame(_ game: SaveBotGameRequest, token: String) async throws -> SavedBotGame {
        throw APIError.server(status: 401, code: "unauthorized", message: "Not stubbed.")
    }
}

/// The expectations of the site's `authed-bots.test.ts`, on the bundled mirror.
@Suite struct PlayCatalogueTests {
    private let catalogue: PlayCatalogue

    init() throws {
        catalogue = try BundledPlayCatalogue.load()
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

    @Test func tiersFollowTheSitesThresholds() {
        #expect(catalogue.tiers.map(\.id) == ["beginner", "club", "advanced", "expert"])
        #expect(catalogue.tiers.allSatisfy { !$0.label.isEmpty && !$0.blurb.isEmpty })
        func tier(_ rating: Int) -> String {
            rating < 900 ? "beginner" : rating < 1400 ? "club" : rating < 1900 ? "advanced" : "expert"
        }
        #expect(catalogue.bots.allSatisfy { $0.tier == tier($0.rating) })
        #expect(catalogue.tiers.map { catalogue.bots(in: $0).count } == [10, 10, 10, 11])
        #expect(catalogue.bots(in: catalogue.tiers[1]).first?.name == "Jack")
    }

    @Test func portraitsAndFlavourAreTheSites() {
        let byID = Dictionary(uniqueKeysWithValues: catalogue.bots.map { ($0.id, $0) })
        #expect(byID["france"]?.avatar == "/bots/french.webp")
        #expect(byID["usa"]?.avatar == "/bots/american.webp")
        #expect(byID["russia"]?.avatar == "/bots/russian.webp")
        #expect(byID["france"]?.rating == 723)
        #expect(byID["usa"]?.rating == 945)
        #expect(byID["russia"]?.rating == 1086)
        #expect(byID["france"]?.name == "Étienne")
        for bot in catalogue.bots where !["france", "usa", "russia"].contains(bot.id) {
            #expect(bot.avatar == "/bots/\(bot.id).webp")
        }
        let openers: Set<String> = ["e2e4", "d2d4", "c2c4", "g1f3"]
        #expect(catalogue.bots.allSatisfy { $0.firstMove.map(openers.contains) == true })
        #expect(catalogue.bots.allSatisfy { (0...1).contains($0.wildness) })
        #expect((catalogue.bots.last?.wildness ?? 1) < (catalogue.bots.first?.wildness ?? 0))
        // Everything is free on the site: no gate is invented here.
        #expect(catalogue.bots.allSatisfy { $0.access == .free })
    }

    @Test func theBuiltOpponentAndTheNetwork() {
        #expect(catalogue.custom.name == "Custom bot")
        #expect(catalogue.custom.minRating == 400)
        #expect(catalogue.custom.maxRating == 2400)
        #expect(catalogue.custom.step == 10)
        #expect(catalogue.custom.defaultRating == 1500)
        #expect(catalogue.custom.wildness == 0.5)
        #expect(catalogue.maia?.model == "maia3-5m")
        #expect(catalogue.maia?.url.absoluteString.hasSuffix("/maia3-5m.onnx") == true)
    }

    @Test func bothClientsServeTheSameCatalogue() async throws {
        #expect(try await FixtureAPI(delay: .zero).playBots(token: nil) == catalogue)
        // Until the endpoint is live, the live client answers from the bundle too.
        #expect(!PlayEndpoints.areLive)
        let live = LiveAPI(baseURL: try #require(URL(string: "https://example.invalid")))
        #expect(try await live.playBots(token: nil) == catalogue)
        #expect(!live.savesBotGames)
    }

    @Test func theServerMayGateABotAndOmitWhatIsOptional() throws {
        let json = """
        {"tiers":[{"id":"club","label":"Club","blurb":"x"}],
         "bots":[
          {"id":"a","name":"A","country":"Peru","rating":900,"tier":"club","avatar":"/bots/a.webp","tagline":"t","wildness":0.5},
          {"id":"b","name":"B","country":"Peru","rating":950,"tier":"club","avatar":"https://cdn.example/b.webp","tagline":"t","firstMove":"e2e4","wildness":0.4,"access":"premium","extra":1},
          {"id":"c","name":"C","country":"Peru","rating":990,"tier":"club","avatar":"/bots/c.webp","tagline":"t","wildness":0.4,"access":"account"},
          {"id":"d","name":"D","country":"Peru","rating":999,"tier":"club","avatar":"/bots/d.webp","tagline":"t","wildness":0.4,"access":"something-new"}],
         "custom":{"name":"Custom bot","avatar":"/bots/placeholder.webp","minRating":400,"maxRating":2400,"step":10,"defaultRating":1500,"wildness":0.5}}
        """
        let decoded: PlayCatalogue = try LiveAPI.decode(status: 200, data: Data(json.utf8))
        #expect(decoded.bots.map(\.access) == [.free, .premium, .account, .premium])
        #expect(decoded.bots[0].firstMove == nil)
        #expect(decoded.maia == nil)
    }
}
