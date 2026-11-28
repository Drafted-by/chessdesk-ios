import SwiftUI

/// What the home opens over the whole app: the trainers take the screen.
enum HomeCover: Hashable, Identifiable {
    case daily
    case mistakes
    case patternDrill(key: String)
    case repertoireReview(id: String)
    case courseReview(slug: String)

    var id: Self { self }
}

/// Opens the destinations of `HomeRoute`, from Today, Progress, You and the
/// Train hub. A trainer is a cover over the whole app; a section is a tab;
/// a game, a course or Progress is pushed on Today's stack.
@Observable
final class HomeNavigator {
    var cover: HomeCover?
    /// Bumped when a trainer closes, so the home and progress read again.
    private(set) var revision = 0
    @ObservationIgnored private let app: AppNavigator

    init(app: AppNavigator) {
        self.app = app
    }

    func open(_ route: HomeRoute) {
        switch route {
        case .daily: cover = .daily
        case .mistakes: cover = .mistakes
        case let .patternDrill(key): cover = .patternDrill(key: key)
        case let .repertoire(id): cover = .repertoireReview(id: id)
        case let .courseReview(slug): cover = .courseReview(slug: slug)
        case .courses: app.show(.learn)
        case .games: app.show(.games)
        case .play: app.show(.play)
        case .puzzles: app.open(AppRoute.puzzles, in: .train)
        case .repertoires: app.open(AppRoute.repertoires, in: .learn)
        case .game, .path, .course, .progress:
            app.push(route, in: .today)
            app.show(.today)
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
}

/// A tappable way to a home destination.
struct HomeRouteLink<Label: View>: View {
    let route: HomeRoute
    @ViewBuilder let label: () -> Label

    @Environment(HomeNavigator.self) private var navigator

    var body: some View {
        Button { navigator.open(route) } label: { label() }
            .buttonStyle(CDPressStyle())
    }
}

/// The same way in, as a button of the kit: an action inside a card.
struct HomeRouteButton: View {
    let title: String
    let route: HomeRoute
    var variant: CDButtonStyle.Variant = .secondary
    var size: CDButtonStyle.Size = .medium
    var fullWidth = false
    /// A trailing arrow: the button leads somewhere else.
    var leads = true

    @Environment(HomeNavigator.self) private var navigator

    var body: some View {
        Button { navigator.open(route) } label: {
            HStack(spacing: CD.Space.s6) {
                Text(title)
                if leads { Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold)) }
            }
        }
        .buttonStyle(.cd(variant, size: size, fullWidth: fullWidth))
    }
}

extension View {
    /// The screens the home pushes, on Today's stack.
    func homeDestinations(_ navigator: HomeNavigator) -> some View {
        navigationDestination(for: HomeRoute.self) { route in
            switch route {
            case let .game(id): GameScreen(id: id, onReviewed: { navigator.refresh() })
            case let .path(slug): PathView(slug: slug)
            case let .course(slug): CourseDetailView(slug: slug)
            case .progress: ProgressScreen()
            // Covers and sections: `HomeNavigator.open` never pushes them.
            case .daily, .mistakes, .patternDrill, .repertoire, .courseReview, .courses, .games, .puzzles, .repertoires, .play:
                EmptyView()
            }
        }
    }

    /// The trainers the home opens, over the whole app: attached once, to the root.
    func homeCovers(_ navigator: HomeNavigator) -> some View {
        modifier(HomeCovers(navigator: navigator))
    }
}

private struct HomeCovers: ViewModifier {
    @Bindable var navigator: HomeNavigator

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $navigator.cover, onDismiss: { navigator.refresh() }) { cover in
            switch cover {
            case .daily:
                DailyScreen { next in navigator.closeCover(then: next) }
            case .mistakes:
                MistakeTrainerScreen()
            case let .patternDrill(key):
                PatternDrillScreen(key: key) { navigator.closeCover() }
            case let .repertoireReview(id):
                RepertoireTrainerScreen(request: RepertoireTrainingRequest(id: id, name: "", mode: .review))
            case let .courseReview(slug):
                CourseReviewScreen(slug: slug)
            }
        }
    }
}

/// The review of a course opened by its slug alone (a step of the plan, a
/// row of the due card): reads the course for its name, then runs the trainer.
struct CourseReviewScreen: View {
    let slug: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var trainerIsUp = false

    var body: some View {
        Loadable(
            id: AnyHashable(slug),
            failureTitle: "Your review did not load",
            load: { try await app.api.course(slug: slug, token: app.token) },
            content: { course in
                TrainerScreen(request: TrainerRequest(course: course, mode: .review, line: nil))
                    .onAppear { trainerIsUp = true }
            }
        )
        .overlay(alignment: .topLeading) {
            // The trainer brings its own close button once it is there.
            if !trainerIsUp {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(CD.ink2)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close")
                .padding(.leading, CD.Space.s4)
            }
        }
        .background(CD.canvas.ignoresSafeArea())
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
