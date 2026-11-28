import SwiftUI

/// What the Train hub knows about a signed-in player: the figures the
/// server gave, read from the home and the Woodpecker overview.
nonisolated struct TrainState: Hashable, Sendable {
    var puzzleRating: Int?
    var daily: PlayerHome.Daily?
    var mistakes: PlayerHome.Mistakes?
    var woodpecker: WoodpeckerRun.OpenCycle?

    init(home: PlayerHome? = nil, woodpecker: WoodpeckerOverview? = nil) {
        puzzleRating = home?.puzzleRating.map { Int($0.rounded()) }
        daily = home?.daily
        mistakes = home?.mistakes
        self.woodpecker = woodpecker?.run?.openCycle
    }
}

/// One way to train, as a row of the hub.
enum TrainRow: String, CaseIterable, Identifiable, Sendable {
    case puzzles, woodpecker, daily, mistakes, coordinates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .puzzles: "Puzzles"
        case .woodpecker: "Woodpecker"
        case .daily: "Daily 5"
        case .mistakes: "Your mistakes"
        case .coordinates: "Coordinates"
        }
    }

    var symbol: String {
        switch self {
        case .puzzles: "puzzlepiece"
        case .woodpecker: "arrow.triangle.2.circlepath"
        case .daily: "calendar"
        case .mistakes: "arrow.uturn.backward"
        case .coordinates: "square.grid.3x3"
        }
    }

    /// What it is, in one line.
    var summary: String {
        switch self {
        case .puzzles: "Tactics at your level, one position at a time."
        case .woodpecker: "One set of puzzles, solved faster each cycle."
        case .daily: "Five positions a day, from your own games."
        case .mistakes: "Where your games went wrong, until you find the better move."
        case .coordinates: "Tap the named square, as many as you can in 30 seconds."
        }
    }

    /// Whether the feature belongs to an account. Puzzles have a free set
    /// and the coordinates run on the phone alone.
    var needsAccount: Bool {
        switch self {
        case .puzzles, .coordinates: false
        case .woodpecker, .daily, .mistakes: true
        }
    }

    /// What a guest reads under the row.
    func line(isSignedIn: Bool) -> String {
        if isSignedIn || !needsAccount { return summary }
        return "\(summary) Needs an account."
    }

    /// The figure of the row, when the server gave one.
    func state(_ state: TrainState?) -> (text: String, isDue: Bool)? {
        guard let state else { return nil }
        switch self {
        case .puzzles:
            return state.puzzleRating.map { ("Rating \(CDFormat.count($0))", false) }
        case .woodpecker:
            return state.woodpecker.map {
                ("Cycle \($0.cycleNumber) · \(CDFormat.count($0.solved)) of \(CDFormat.count($0.total))", false)
            }
        case .daily:
            guard let daily = state.daily else { return nil }
            let streak = daily.streak.current > 0 ? " · \(CDFormat.count(daily.streak.current))-day streak" : ""
            return daily.doneToday ? ("Done today\(streak)", false) : ("Open today\(streak)", true)
        case .mistakes:
            guard let mistakes = state.mistakes, mistakes.total > 0 else { return nil }
            return mistakes.due > 0 ? ("\(CDFormat.count(mistakes.due)) due", true) : ("Nothing due", false)
        case .coordinates:
            return nil
        }
    }
}

/// "Train": the ways to practise, as a list. A working screen: rows, no
/// ornament. A row says in one line what it is and shows its state when the
/// server gave one; a row that needs an account says so to a guest, and
/// opens a screen that offers one.
struct TrainHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var home
    @State private var state: TrainState?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                Text("Train")
                    .cdFont(.display)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: 0) {
                    ForEach(Array(TrainRow.allCases.enumerated()), id: \.element) { index, row in
                        if index > 0 { CDHairline() }
                        entry(row)
                    }
                }
                .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
                .hairline()
            }
            .pageGutter()
            .padding(.top, CD.Space.s24)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Train")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
        // Read when the hub appears (also on the way back from a trainer),
        // when the account changes and when a trainer over the app closes.
        .task(id: [app.accountRevision, home.revision]) { await load() }
    }

    private func load() async {
        guard let token = app.playerToken else {
            state = nil
            return
        }
        async let overview = try? app.api.woodpecker(token: token)
        let home = try? await app.api.home(token: token)
        let fresh = TrainState(home: home, woodpecker: await overview)
        if !Task.isCancelled { state = fresh }
    }

    /// A row leads to its screen; for a guest, the two that have no screen
    /// of their own without an account lead to what an account brings.
    @ViewBuilder private func entry(_ row: TrainRow) -> some View {
        switch row {
        case .puzzles:
            NavigationLink(value: AppRoute.puzzles) { label(row) }.buttonStyle(CDPressStyle())
        case .woodpecker:
            NavigationLink(value: AppRoute.woodpecker) { label(row) }.buttonStyle(CDPressStyle())
        case .coordinates:
            NavigationLink(value: AppRoute.coordinates) { label(row) }.buttonStyle(CDPressStyle())
        case .daily:
            if app.isSignedIn {
                Button { home.open(.daily) } label: { label(row) }.buttonStyle(CDPressStyle())
            } else {
                NavigationLink {
                    TrainAccountScreen(
                        title: "Daily 5",
                        heading: "Five positions a day, from your own games",
                        message: "Each day, five positions where one of your games went wrong, and a streak that grows with the days you train. It is built from the games of an account."
                    )
                } label: { label(row) }
                    .buttonStyle(CDPressStyle())
            }
        case .mistakes:
            if app.isSignedIn {
                Button { home.open(.mistakes) } label: { label(row) }.buttonStyle(CDPressStyle())
            } else {
                NavigationLink {
                    TrainAccountScreen(
                        title: "Your mistakes",
                        heading: "Your own mistakes, until they are gone",
                        message: "Bring in your games from Chess.com or Lichess, have the engine on this phone review them, and the positions where you went wrong come back until you find the better move. It needs an account."
                    )
                } label: { label(row) }
                    .buttonStyle(CDPressStyle())
            }
        }
    }

    private func label(_ row: TrainRow) -> some View {
        let figure = row.state(state)
        return HStack(spacing: CD.Space.s12) {
            Image(systemName: row.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(CD.accent)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(row.title)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                    Spacer(minLength: CD.Space.s4)
                    if let figure {
                        Text(figure.text)
                            .cdFont(.small)
                            .foregroundStyle(figure.isDue ? CD.accentStrong : CD.ink3)
                            .cdNumber()
                            .lineLimit(1)
                    }
                }
                Text(row.line(isSignedIn: app.isSignedIn))
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .padding(.horizontal, CD.Space.s16)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 64)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// What a trainer that belongs to an account shows a guest: what it is, and
/// the two ways in. Once signed in, the trainer itself is one tap back.
private struct TrainAccountScreen: View {
    let title: String
    let heading: String
    let message: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            AccountNeededView(title: heading, message: message)
                .pageGutter()
                .padding(.vertical, CD.Space.s16)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .cdPage()
        // Signed in from here: back to the hub, where the row now opens the trainer.
        .onChange(of: app.isSignedIn) { _, signedIn in if signedIn { dismiss() } }
    }
}

#Preview {
    NavigationStack { TrainHubView().appDestinations() }
}
