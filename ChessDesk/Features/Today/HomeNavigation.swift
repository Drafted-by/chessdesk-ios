import SwiftUI

/// What the home opens over itself: the trainers take the whole screen.
enum HomeCover: Hashable, Identifiable {
    case daily
    case mistakes
    case patternDrill(key: String)

    var id: Self { self }
}

/// Opens the destinations of `HomeRoute` from Today and Progress. Pushed
/// screens go through `NavigationLink(value:)`; the trainers are covers; the
/// course catalogue is a tab.
@Observable
final class HomeNavigator {
    var cover: HomeCover?
    var showsProgress = false
    /// Bumped when a trainer closes, so the home and progress read again.
    private(set) var revision = 0
    @ObservationIgnored var openCourses: () -> Void = {}
    @ObservationIgnored var openGames: () -> Void = {}

    func open(_ route: HomeRoute) {
        switch route {
        case .daily: cover = .daily
        case .mistakes: cover = .mistakes
        case let .patternDrill(key): cover = .patternDrill(key: key)
        case .courses: openCourses()
        case .games: openGames()
        case .progress: showsProgress = true
        case .game, .path, .course, .play, .puzzles, .repertoire, .repertoires: break
        }
    }

    /// A trainer closed; `next` is where the player asked to go.
    func closeCover(then next: HomeRoute? = nil) {
        cover = nil
        revision += 1
        guard let next else { return }
        Task {
            // Let the cover go before pushing.
            try? await Task.sleep(for: .milliseconds(450))
            open(next)
        }
    }

    func refresh() { revision += 1 }

    /// Whether a route is a pushed screen (otherwise `open` handles it).
    static func pushes(_ route: HomeRoute) -> Bool {
        switch route {
        case .game, .path, .course, .play, .puzzles, .repertoire, .repertoires: true
        case .daily, .mistakes, .patternDrill, .courses, .games, .progress: false
        }
    }
}

/// A tappable way to a home destination.
struct HomeRouteLink<Label: View>: View {
    let route: HomeRoute
    @ViewBuilder let label: () -> Label

    @Environment(HomeNavigator.self) private var navigator

    var body: some View {
        if HomeNavigator.pushes(route) {
            NavigationLink(value: route, label: label)
                .buttonStyle(CDPressStyle())
        } else {
            Button { navigator.open(route) } label: { label() }
                .buttonStyle(CDPressStyle())
        }
    }
}

extension View {
    /// The screens the home leads to, on the stack of the view it is attached to.
    func homeDestinations(_ navigator: HomeNavigator) -> some View {
        modifier(HomeDestinations(navigator: navigator))
    }
}

private struct HomeDestinations: ViewModifier {
    @Bindable var navigator: HomeNavigator

    func body(content: Content) -> some View {
        content
            .environment(navigator)
            .navigationDestination(for: HomeRoute.self) { route in
                screen(route).environment(navigator)
            }
            .navigationDestination(isPresented: $navigator.showsProgress) {
                ProgressScreen().environment(navigator)
            }
            .fullScreenCover(item: $navigator.cover, onDismiss: { navigator.refresh() }) { cover in
                switch cover {
                case .daily:
                    DailyScreen { next in navigator.closeCover(then: next) }
                case .mistakes:
                    MistakeTrainerScreen()
                case let .patternDrill(key):
                    PatternDrillScreen(key: key) { navigator.closeCover() }
                }
            }
    }

    /// The pushed screens. Puzzles and repertoires are built on other
    /// branches: the pilot puts their screens here and turns them on in
    /// `HomeRouter.opens`.
    @ViewBuilder private func screen(_ route: HomeRoute) -> some View {
        switch route {
        case let .game(id): GameScreen(id: id, onReviewed: { navigator.refresh() })
        case let .path(slug): PathView(slug: slug)
        case let .course(slug): CourseDetailView(slug: slug)
        case .play: PlayHubView()
        case .progress: ProgressScreen()
        case .puzzles, .repertoire, .repertoires, .daily, .mistakes, .patternDrill, .courses, .games: EmptyView()
        }
    }
}

extension View {
    /// Debug builds: `-CDScrollAnchor 0.6` opens a long screen scrolled to that
    /// fraction of its height, to look at it in the simulator without touching it.
    @ViewBuilder func debugScrollAnchor() -> some View {
        #if DEBUG
            if let text = UserDefaults.standard.string(forKey: "CDScrollAnchor"), let fraction = Double(text) {
                defaultScrollAnchor(UnitPoint(x: 0.5, y: fraction))
            } else {
                self
            }
        #else
            self
        #endif
    }
}
