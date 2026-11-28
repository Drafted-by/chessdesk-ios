import SwiftUI

/// The app's five sections, in the order of the tab bar. A section appears
/// here when it works end to end; there are no "coming soon" tabs.
enum AppSection: Hashable, CaseIterable {
    case today, learn, play, train, games

    var title: String {
        switch self {
        case .today: "Today"
        case .learn: "Learn"
        case .play: "Play"
        case .train: "Train"
        case .games: "Games"
        }
    }

    var symbol: String {
        switch self {
        case .today: "sun.max"
        case .learn: "book.closed"
        case .play: "person.2"
        case .train: "target"
        case .games: "flag.checkered"
        }
    }
}

/// A screen that any section can push on its own stack.
enum AppRoute: Hashable {
    /// The account, Premium, the settings, the board, about.
    case you
    case progress
    case repertoires
    case puzzles
    case woodpecker
    case coordinates
    case explorer
    /// Best move and the Elo calculator.
    case tools
    case tool(ToolRoute)
}

/// Where the player is: the section shown and what each section has pushed.
/// One per window, in the environment; a screen that sends the player to
/// another section asks it.
@Observable
final class AppNavigator {
    var section: AppSection = .today
    var today = NavigationPath()
    var learn = NavigationPath()
    var play = NavigationPath()
    var train = NavigationPath()
    var games = NavigationPath()

    /// Shows a section as the player left it.
    func show(_ section: AppSection) {
        self.section = section
    }

    /// Shows a section and pushes a screen on it, from its first screen.
    func open(_ route: some Hashable, in section: AppSection) {
        var path = NavigationPath()
        path.append(route)
        setPath(path, of: section)
        self.section = section
    }

    /// Pushes a further screen on a section, over what is there.
    func push(_ route: some Hashable, in section: AppSection) {
        var path = path(of: section)
        path.append(route)
        setPath(path, of: section)
    }

    func path(of section: AppSection) -> NavigationPath {
        switch section {
        case .today: today
        case .learn: learn
        case .play: play
        case .train: train
        case .games: games
        }
    }

    private func setPath(_ path: NavigationPath, of section: AppSection) {
        switch section {
        case .today: today = path
        case .learn: learn = path
        case .play: play = path
        case .train: train = path
        case .games: games = path
        }
    }
}

extension View {
    /// The screens of `AppRoute` and `CourseRoute`, on the stack of the view
    /// it is attached to: every section opens them the same way.
    func appDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .you: AccountView()
            case .progress: ProgressScreen()
            case .repertoires: RepertoiresView()
            case .puzzles: PuzzlesHubView()
            case .woodpecker: WoodpeckerScreen()
            case .coordinates: CoordinateTrainerScreen()
            case .explorer: ExplorerView()
            case .tools: ToolsHubView()
            case let .tool(tool): tool.screen
            }
        }
        .navigationDestination(for: CourseRoute.self) { route in
            switch route {
            case let .course(slug): CourseDetailView(slug: slug)
            case let .path(slug): PathView(slug: slug)
            }
        }
    }
}

/// The way to You from Today: the player's initial, or a person for a guest.
struct ProfileButton: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationLink(value: AppRoute.you) {
            Group {
                if let initial = app.me?.user.name.trimmingCharacters(in: .whitespaces).first {
                    Text(String(initial).uppercased())
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                } else {
                    Image(systemName: "person")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(CD.ink2)
                }
            }
            .frame(width: 36, height: 36)
            .background(CD.surface2, in: Circle())
            .overlay(Circle().strokeBorder(CD.lineStrong, lineWidth: 1))
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .accessibilityLabel(app.isSignedIn ? "You: your account and settings" : "You: account and settings")
    }
}

/// The top of Today: the wordmark, and the way to You at the right.
struct TodayTopBar: View {
    var body: some View {
        HStack(alignment: .center) {
            Wordmark(size: 20)
            Spacer()
            ProfileButton()
        }
        .padding(.trailing, -CD.Space.s4)
    }
}

/// What a screen shows a guest when it needs an account: what the feature
/// is, and the two ways in.
struct AccountNeededView: View {
    let title: String
    let message: String

    @State private var signIn: SignInView.Mode?

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text(title)
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message)
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create an account") { signIn = .createAccount }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .padding(.top, CD.Space.s4)
                Button("Sign in") { signIn = .signIn }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
            }
        }
        .sheet(item: $signIn) { SignInView(mode: $0) }
    }
}
