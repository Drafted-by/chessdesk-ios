import SwiftUI

/// The app: five sections in a tab bar, each with a stack of its own.
///
/// - Today: the guest's first screen, or the signed-in plan. The profile
///   button at its top right opens You (the account, Premium, the settings,
///   the board, about, the way to Progress).
/// - Learn: the courses and the learning paths, and the player's repertoires.
/// - Play: the bots.
/// - Train: puzzles, Woodpecker, Daily 5, the player's mistakes, coordinates.
/// - Games: the player's games, the explorer, the analysis board, the tools.
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var navigator: AppNavigator
    @State private var home: HomeNavigator
    @State private var accountSettings = AccountSettingsModel()
    @AppStorage(FirstLaunchView.seenKey) private var firstLaunchSeen = false
    @State private var showsFirstLaunch = false
    #if DEBUG
        @State private var debugBoardSettings = false
    #endif

    init() {
        let navigator = AppNavigator()
        _navigator = State(initialValue: navigator)
        _home = State(initialValue: HomeNavigator(app: navigator))
    }

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.section) {
            NavigationStack(path: $navigator.today) {
                TodayView()
                    .appDestinations()
                    .homeDestinations(home)
                #if DEBUG
                    // `-CDRoute boardsettings`: You › Board and sound on its own, to look at it whole.
                    .navigationDestination(isPresented: $debugBoardSettings) {
                        ScrollView { BoardSettingsSection().pageGutter().padding(.vertical, CD.Space.s16) }
                            .cdPage()
                    }
                #endif
            }
            .tab(.today)

            NavigationStack(path: $navigator.learn) {
                LearnView().appDestinations()
            }
            .tab(.learn)

            NavigationStack(path: $navigator.play) {
                PlayHubView().appDestinations()
            }
            .tab(.play)

            NavigationStack(path: $navigator.train) {
                TrainHubView().appDestinations()
            }
            .tab(.train)

            NavigationStack(path: $navigator.games) {
                GamesView().appDestinations()
            }
            .tab(.games)
        }
        .background(CD.canvas)
        .environment(navigator)
        .environment(home)
        .homeCovers(home)
        .fullScreenCover(isPresented: $showsFirstLaunch) {
            FirstLaunchView {
                firstLaunchSeen = true
                showsFirstLaunch = false
            }
        }
        // Once, to someone who has never opened the app and has no session.
        .task {
            #if DEBUG
                if let route = DebugLaunch.route {
                    showsFirstLaunch = route.first == "firstlaunch"
                    return
                }
            #endif
            if !firstLaunchSeen, app.token == nil { showsFirstLaunch = true } else { firstLaunchSeen = true }
        }
        // The account's settings, its board included, follow who is signed in.
        .environment(accountSettings)
        .task(id: app.accountRevision) { await accountSettings.attach(api: app.api, token: app.isSignedIn ? app.token : nil) }
        #if DEBUG
            .debugCanvas()
            .task { await openDebugRoute() }
        #endif
    }

    #if DEBUG
        /// `-CDRoute <route>` opens a screen directly, to check it in the
        /// simulator. A route names a section, or a screen and what it shows:
        ///
        /// - `today`, `learn` (or `courses`), `play`, `train`, `games`: a section.
        /// - `firstlaunch`: the first-launch screen, which no other route shows.
        /// - `you` (or `account`), `account/signin`, `account/signup`,
        ///   `account/delete`, `boardsettings`; `progress`, `daily`,
        ///   `drill/<key>`, `game/<id>` and `deck/<deck>` (the review of a
        ///   deck: `deck/course:<slug>`, `deck/repertoire:<id>`) for a
        ///   signed-in player.
        /// - `course/<slug>`, `trainer/<slug>`, `path`, `stage/<stage slug>`,
        ///   `premium`, `repertoires`, `repertoires/new`, `repertoires/<id>`,
        ///   `repertoires/<id>/train`, `repertoires/<id>/games`.
        /// - `play/<bot id>`, `play/custom`, `play/resume`.
        /// - `puzzles`, `puzzles/free`, `puzzles/rated`, `woodpecker`,
        ///   `coordinates`, `mistakes`.
        /// - `games/sample`, `explorer`, `tools`, `analysis`, `bestmove`, `elo`.
        ///
        /// The screens read the rest of the route and their own options
        /// themselves (`DebugLaunch`, `PlayDebug`, `RepertoireDebug`…).
        private func openDebugRoute() async {
            guard let route = DebugLaunch.route, let first = route.first else { return }
            switch first {
            case "today": navigator.show(.today)
            case "learn", "courses": navigator.show(.learn)
            case "course", "trainer":
                guard route.count > 1 else { return }
                navigator.open(CourseRoute.course(slug: route[1]), in: .learn)
            case "path", "stage", "premium": navigator.open(CourseRoute.path(slug: FeaturedPath.slug), in: .learn)
            case "repertoires": navigator.open(AppRoute.repertoires, in: .learn)
            case "play": navigator.show(.play)
            case "train": navigator.show(.train)
            case "puzzles": navigator.open(AppRoute.puzzles, in: .train)
            case "woodpecker": navigator.open(AppRoute.woodpecker, in: .train)
            case "coordinates": navigator.open(AppRoute.coordinates, in: .train)
            case "games": navigator.show(.games)
            case "explorer": navigator.open(AppRoute.explorer, in: .games)
            case "tools": navigator.open(AppRoute.tools, in: .games)
            case "analysis", "bestmove", "elo":
                if let tool = ToolRoute(rawValue: first) { navigator.open(AppRoute.tool(tool), in: .games) }
            case "you", "account": navigator.open(AppRoute.you, in: .today)
            case "boardsettings": debugBoardSettings = true
            case "progress", "daily", "drill", "mistakes", "deck", "game":
                // These need the player: wait for the session to be restored.
                for _ in 0..<100 where !app.isSignedIn { try? await Task.sleep(for: .milliseconds(50)) }
                guard app.isSignedIn else {
                    if first == "mistakes" { navigator.show(.train) }
                    return
                }
                switch first {
                case "progress": home.open(.progress)
                case "daily": home.open(.daily)
                case "mistakes": home.open(.mistakes)
                case "deck": if route.count > 1, let review = HomeRouter.deck(route[1]) { home.open(review) }
                case "game": if route.count > 1 { home.open(.game(id: route[1])) }
                default: if route.count > 1 { home.open(.patternDrill(key: route[1])) }
                }
            default: break
            }
        }
    #endif
}

private extension View {
    func tab(_ section: AppSection) -> some View {
        tabItem { Label(section.title, systemImage: section.symbol) }
            .tag(section)
    }
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

        /// `-CDCanvas 1180x820`: the size the app is laid out for.
        static var canvas: CGSize? {
            guard let text = UserDefaults.standard.string(forKey: "CDCanvas") else { return nil }
            let parts = text.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
        }
    }

    extension View {
        /// `-CDCanvas 1180x820` lays the whole app out for another size, at
        /// regular width, and shrinks it to fit the screen: to look at the
        /// iPad layouts of every screen on a phone simulator. Sheets and
        /// covers keep the size of the device.
        @ViewBuilder func debugCanvas() -> some View {
            if let canvas = DebugLaunch.canvas {
                GeometryReader { proxy in
                    let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
                    self
                        // A canvas narrower than 600 pt is a phone, however tall: a way to see a whole long page.
                        .environment(\.horizontalSizeClass, canvas.width < 600 ? .compact : .regular)
                        .frame(width: canvas.width, height: canvas.height)
                        .scaleEffect(scale, anchor: .topLeading)
                        // The layout keeps the size of the canvas: pin its corner, then centre what is drawn.
                        .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(Color.black.ignoresSafeArea())
            } else {
                self
            }
        }
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
    /// What shows until the value is there; a spinner unless the screen has
    /// something of its own to show at once.
    var placeholder: AnyView = AnyView(LoadingView())
    let load: () async throws -> Value
    @ViewBuilder let content: (Value) -> Content

    @State private var phase: Phase = .loading
    @State private var attempt = 0

    var body: some View {
        Group {
            switch phase {
            case .loading:
                placeholder
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
