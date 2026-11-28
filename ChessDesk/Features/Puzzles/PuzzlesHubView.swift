import SwiftUI

/// Puzzles: the summary of the player's rating and the ways in (the free
/// set, rated puzzles, the Woodpecker Method). A guest solves the free set
/// and reads what an account adds.
struct PuzzlesHubView: View {
    @Environment(AppModel.self) private var app
    @State private var signIn: SignInView.Mode?
    #if DEBUG
        @State private var debugRoute: PuzzlesRoute?
    #endif

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(app.backend), AnyHashable(app.accountRevision)]),
            failureTitle: "Puzzles did not load",
            load: { try await app.api.puzzleOverview(token: app.token) },
            content: { overview in page(overview) }
        )
        .navigationTitle("Puzzles")
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
        .sheet(item: $signIn) { SignInView(mode: $0) }
        #if DEBUG
            .navigationDestination(item: $debugRoute) { $0.screen }
            .onAppear {
                guard !PuzzlesDebug.handled else { return }
                PuzzlesDebug.handled = true
                debugRoute = PuzzlesDebug.screen
            }
        #endif
    }

    private func page(_ overview: PuzzleOverview) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                if let player = overview.player {
                    RatingSummary(player: player)
                    NavigationLink { PuzzlesRoute.rated.screen } label: {
                        Text("Solve rated puzzles")
                    }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    EntryRow(
                        title: "Free puzzles",
                        detail: "\(CDFormat.count(overview.free.puzzles)) unrated puzzles, from easy to hard, with themes to choose.",
                        route: .free
                    )
                } else {
                    guestIntro(overview)
                }
                woodpecker
                if overview.player == nil {
                    AccountPitch(signIn: $signIn, title: "What an account adds", leads: false)
                }
            }
            .puzzlesPage()
        }
    }

    private func guestIntro(_ overview: PuzzleOverview) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            Text("Tactics, one position at a time")
                .cdFont(.pageTitle)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(CDFormat.count(overview.free.puzzles)) free puzzles, from easy to hard. Pick a theme and a difficulty, find the move, and the reply is played for you.")
                .cdFont(.lede)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink { PuzzlesRoute.free.screen } label: {
                Text("Solve free puzzles")
            }
            .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            .padding(.top, CD.Space.s4)
        }
    }

    @ViewBuilder private var woodpecker: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "The Woodpecker Method")
            Text(WoodpeckerCopy.method)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
            if app.isSignedIn {
                EntryRow(title: "Woodpecker", detail: "Your set, your cycles, your times.", route: .woodpecker)
            } else {
                Text("It needs an account, to keep your set and your times.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            }
        }
    }
}

/// The two sentences that explain the method, wherever it is offered.
enum WoodpeckerCopy {
    static let method = "Solve one fixed set of puzzles, then the same set again in timed cycles, each aiming at half the time of the first. After a few cycles the patterns come to you without calculating."
}

/// The player's puzzle rating, the last 30 days and the curve.
private struct RatingSummary: View {
    let player: PuzzlePlayer

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Puzzle rating")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                    Text(CDFormat.count(player.rating))
                        .cdFont(.metric)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                }
                .accessibilityElement(children: .combine)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Last 30 days")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                    Text("\(CDFormat.count(player.last30Days.solved)) of \(CDFormat.count(player.last30Days.attempts)) solved")
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                    if player.last30Days.attempts > 0 {
                        Text("\(Int((Double(player.last30Days.solved) / Double(player.last30Days.attempts) * 100).rounded()))% clean")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
                .accessibilityElement(children: .combine)
            }
            if player.history.count >= 2 {
                RatingCurve(points: player.history)
            }
            Text("\(CDFormat.plural(player.attempts, "puzzle")) played, \(CDFormat.count(player.solved)) solved clean.")
                .cdFont(.meta)
                .foregroundStyle(CD.ink3)
                .cdNumber()
        }
    }
}

/// A row that opens one way in.
private struct EntryRow: View {
    let title: String
    let detail: String
    let route: PuzzlesRoute

    var body: some View {
        NavigationLink { route.screen } label: {
            HStack(spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                    Text(detail)
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: CD.Space.s8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CD.ink4)
            }
            .padding(CD.Space.s16)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
            .hairline()
        }
        .buttonStyle(CDPressStyle())
    }
}

#if DEBUG
    enum PuzzlesDebug {
        /// Set once the route has been followed, so going back stays back.
        static var handled = false

        /// The screen the hub opens: `puzzles/free` or `puzzles/rated`.
        static var screen: PuzzlesRoute? {
            switch DebugLaunch.route ?? [] {
            case ["puzzles", "free"]: .free
            case ["puzzles", "rated"]: .rated
            default: nil
            }
        }
    }
#endif
