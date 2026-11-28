import SwiftUI

/// The app's sections. A section appears here when it works end to end;
/// there are no "coming soon" tabs.
enum AppSection: Hashable {
    case today, courses, games, account
}

struct RootView: View {
    @State private var section: AppSection = .today
    @State private var coursesPath = NavigationPath()

    var body: some View {
        TabView(selection: $section) {
            NavigationStack {
                TodayView(openCourses: { section = .courses })
                    .courseDestinations()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(AppSection.today)

            NavigationStack(path: $coursesPath) {
                CoursesView()
                    .courseDestinations()
                    .repertoiresEntry()
                    .explorerEntry()
            }
            .tabItem { Label("Courses", systemImage: "book.closed") }
            .tag(AppSection.courses)

            NavigationStack {
                GamesView()
            }
            .tabItem { Label("Games", systemImage: "flag.checkered") }
            .tag(AppSection.games)

            NavigationStack {
                AccountView()
            }
            .tabItem { Label("You", systemImage: "person") }
            .tag(AppSection.account)
        }
        .background(CD.canvas)
        #if DEBUG
            .onAppear(perform: openDebugRoute)
        #endif
    }

    #if DEBUG
        /// `-CDRoute courses | account | account/signin | course/<slug> | trainer/<slug> | path | stage/<slug> | premium` opens a
        /// screen directly: used to check screens in the simulator.
        private func openDebugRoute() {
            guard let route = DebugLaunch.route else { return }
            switch route.first {
            case "courses": section = .courses
            case "games": section = .games
            case "account": section = .account
            case "course", "trainer":
                guard route.count > 1 else { return }
                section = .courses
                coursesPath.append(CourseRoute.course(slug: route[1]))
            case "path", "stage", "premium":
                section = .courses
                coursesPath.append(CourseRoute.path(slug: FeaturedPath.slug))
            case "repertoires", "explorer": section = .courses
            default: break
            }
        }
    #endif
}

#if DEBUG
    enum DebugLaunch {
        static var route: [String]? {
            UserDefaults.standard.string(forKey: "CDRoute")?.split(separator: "/").map(String.init)
        }

        /// With `-CDRoute trainer/<slug>`: the course opens its free line.
        static var opensTrainer: Bool { route?.first == "trainer" }
        /// With `-CDRoute stage/<stage slug>`: the featured path opens that stage.
        static var opensStage: String? {
            guard let route, route.first == "stage", route.count > 1 else { return nil }
            return route[1]
        }
        /// With `-CDRoute premium`: the featured path opens the Premium sheet.
        static var opensPremium: Bool { route?.first == "premium" }
        /// With `-CDRoute account/signin`: You opens the sign-in sheet.
        static var opensSignIn: Bool { route == ["account", "signin"] }
        /// With `-CDRoute account/signup`: You opens the account creation sheet.
        static var opensSignUp: Bool { route == ["account", "signup"] }
        /// With `-CDRoute account/delete`: the account deletion sheet, as a preview.
        static var opensDeletion: Bool { route == ["account", "delete"] }
        /// `-CDExercise 2` starts the stage at its second exercise.
        static var exercise: Int { max(1, UserDefaults.standard.integer(forKey: "CDExercise")) - 1 }
        /// `-CDTrainerSteps 5` plays the first moves of the guided pass.
        static var trainerSteps: Int { UserDefaults.standard.integer(forKey: "CDTrainerSteps") }
        /// `-CDTrainerMemory YES` starts in the memory pass.
        static var trainerMemory: Bool { UserDefaults.standard.bool(forKey: "CDTrainerMemory") }
    }
#endif

/// Routes shared by every stack that can open a course.
enum CourseRoute: Hashable {
    case course(slug: String)
    case path(slug: String)
}

/// The path the app puts forward: most players who install a chess app are
/// under 1000, and this is the course made for them.
nonisolated enum FeaturedPath {
    static let slug = "reach-1000-elo"
}

extension View {
    func courseDestinations() -> some View {
        navigationDestination(for: CourseRoute.self) { route in
            switch route {
            case let .course(slug): CourseDetailView(slug: slug)
            case let .path(slug): PathView(slug: slug)
            }
        }
    }

    /// The standard page: canvas behind, content scrolls over it.
    func cdPage() -> some View {
        background(CD.canvas.ignoresSafeArea())
            .toolbarBackground(CD.canvas, for: .navigationBar)
    }
}

/// Loads a value when the view appears and whenever `id` changes, and keeps
/// what the three states look like in one place.
struct Loadable<Value, Content: View>: View {
    enum Phase {
        case loading
        case loaded(Value)
        case failed(APIError)
    }

    let id: AnyHashable
    let failureTitle: String
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var phase: Phase = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView()
            case let .loaded(value):
                content(value)
            case let .failed(error):
                LoadFailureView(title: failureTitle, message: error.message) {
                    phase = .loading
                    attempt += 1
                }
            }
        }
        .task(id: [id, AnyHashable(attempt)]) {
            do {
                phase = .loaded(try await load())
            } catch is CancellationError {
                // The view went away or reloaded; nothing to show.
            } catch let error as APIError {
                phase = .failed(error)
            } catch {
                phase = .failed(.unreadable)
            }
        }
    }
}
