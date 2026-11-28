import SwiftUI

extension View {
    /// A temporary way into the repertoires, until the feature has its place
    /// in the navigation: a row above the tab bar of the screen it is
    /// attached to. Also where `-CDRoute repertoires` lands.
    func repertoiresEntry() -> some View {
        modifier(FeatureEntry(title: "Your repertoires", route: "repertoires") { RepertoiresView() })
    }
}

/// A row above the tab bar that pushes a screen: how a feature is reached
/// before the pilot gives it its place.
struct FeatureEntry<Destination: View>: ViewModifier {
    let title: String
    /// The first component of the `-CDRoute` that opens it.
    let route: String
    @ViewBuilder let destination: () -> Destination

    @State private var isOpen = false

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Button {
                    isOpen = true
                } label: {
                    HStack(spacing: CD.Space.s8) {
                        Text(title)
                            .cdFont(.bodyStrong)
                            .foregroundStyle(CD.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(CD.ink4)
                    }
                    .padding(.horizontal, CD.Space.s16)
                    .frame(minHeight: 48)
                    .background(CD.surface2)
                    .overlay(alignment: .top) { CDHairline(color: CD.lineStrong) }
                }
                .buttonStyle(CDPressStyle())
            }
            .navigationDestination(isPresented: $isOpen) { destination() }
            #if DEBUG
            .onAppear {
                // Once per launch: coming back to the tab must not open it again.
                if DebugLaunch.route?.first == route, FeatureEntryDebug.opened.insert(route).inserted { isOpen = true }
            }
            #endif
    }
}

#if DEBUG
    enum FeatureEntryDebug {
        static var opened: Set<String> = []
    }

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
    /// - `-CDFixturePremium YES`: the sample player has Premium;
    ///   `-CDSampleGuest YES`: the screens as a guest sees them.
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
