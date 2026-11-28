import SwiftUI

#if DEBUG
    /// Launch arguments for checking the repertoires in the simulator, on
    /// sample data:
    ///
    /// - `-CDRoute repertoires`: the list; `repertoires/new`: the creation sheet.
    /// - `-CDRoute repertoires/<id>`: the builder of a repertoire (the sample
    ///   one is `sample-italian`); `-CDBuilderPath e2e4,e7e5` stands on a
    ///   position, `-CDBuilderAdd d7d6` then adds a move, `-CDBuilderSource
    ///   masters|mine` chooses the numbers, `-CDBuilderSheet tree|note|importPGN`
    ///   opens a sheet (`-CDBuilderPGN "1. d4 d5"` fills the import).
    /// - `-CDRoute repertoires/<id>/train` opens the trainer (`-CDTrainMode
    ///   learn|review`); `repertoires/<id>/games` the games against it.
    /// - They are the sample player's: launch with `-CDFixturePlayer YES`
    ///   (`-CDFixturePremium YES` gives the player Premium). Without it the
    ///   screens are a guest's.
    enum RepertoireDebug {
        /// The route is acted on once per launch.
        static var consumed = false

        private static var defaults: UserDefaults { .standard }
        private static var route: [String] {
            guard let route = DebugLaunch.route, route.first == "repertoires" else { return [] }
            return route
        }

        static var sheet: BuilderSheet? {
            defaults.string(forKey: "CDBuilderSheet").flatMap(BuilderSheet.init(rawValue:))
        }

        static var opensTraining: Bool { route.count > 2 && route[2] == "train" }
        static var opensGames: Bool { route.count > 2 && route[2] == "games" }
        static var trainingMode: SessionMode? {
            defaults.string(forKey: "CDTrainMode").flatMap(SessionMode.init(rawValue:))
        }

        static var samplePGN: String? { defaults.string(forKey: "CDBuilderPGN") }

        /// Loads the repertoire and brings the builder to the asked state.
        static func prepare(_ model: RepertoireBuilderModel) async {
            await model.load()
            if let source = defaults.string(forKey: "CDBuilderSource").flatMap(StatsSource.init(rawValue:)) {
                model.source = source
            }
            let path = defaults.string(forKey: "CDBuilderPath")?.split(separator: ",").map(String.init) ?? []
            if !path.isEmpty { model.goTo(path) }
            if let added = defaults.string(forKey: "CDBuilderAdd") { await model.add(added) }
        }
    }
#endif
