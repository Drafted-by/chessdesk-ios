import SwiftUI

extension View {
    /// A temporary way into the explorer of the player's own games, until the
    /// feature has its place in the navigation. Also where `-CDRoute explorer`
    /// lands.
    func explorerEntry() -> some View {
        modifier(FeatureEntry(title: "Explorer of your games", route: "explorer") { ExplorerView() })
    }
}

#if DEBUG
    /// Launch arguments for checking the explorer in the simulator, on sample
    /// data: `-CDRoute explorer`, `-CDExplorerSide black`, `-CDExplorerPath
    /// e4,e5,Nf3` (SAN), `-CDExplorerTime BLITZ,RAPID` (a filter), and
    /// `-CDExplorerFilters YES` opens the filters.
    enum ExplorerDebug {
        private static var defaults: UserDefaults { .standard }

        static var opensFilters: Bool { defaults.bool(forKey: "CDExplorerFilters") }

        static func prepare(_ model: ExplorerModel) async {
            await model.load()
            if defaults.string(forKey: "CDExplorerSide") == "black" { model.choose(side: .black) }
            if let classes = defaults.string(forKey: "CDExplorerTime") {
                var filters = model.filters
                filters.timeClasses = Set(classes.split(separator: ",").map(String.init))
                model.apply(filters)
            }
            let path = defaults.string(forKey: "CDExplorerPath")?.split(separator: ",").map(String.init) ?? []
            if !path.isEmpty { model.go(to: path) }
            await model.settled()
        }
    }
#endif
