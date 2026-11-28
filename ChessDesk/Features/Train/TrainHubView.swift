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

    var emblem: Emblem.Kind {
        switch self {
        case .puzzles: .puzzles
        case .woodpecker: .woodpecker
        case .daily: .schedule
        case .mistakes: .mistakes
        case .coordinates: .coordinates
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
    func figure(_ state: TrainState?) -> FeatureRow.Figure? {
        guard let state else { return nil }
        switch self {
        case .puzzles:
            return state.puzzleRating.map { .init(value: CDFormat.count($0), caption: "rating") }
        case .woodpecker:
            return state.woodpecker.map {
                .init(value: "Cycle \($0.cycleNumber)", caption: "\(CDFormat.count($0.solved)) of \(CDFormat.count($0.total))")
            }
        case .daily:
            guard let daily = state.daily else { return nil }
            let streak = daily.streak.current > 0 ? "\(CDFormat.count(daily.streak.current))-day streak" : nil
            return daily.doneToday
                ? .init(value: "Done today", caption: streak)
                : .init(value: "Open today", caption: streak, isDue: true)
        case .mistakes:
            guard let mistakes = state.mistakes, mistakes.total > 0 else { return nil }
            return mistakes.due > 0
                ? .init(value: CDFormat.count(mistakes.due), caption: "due", isDue: true)
                : .init(value: "Nothing due")
        case .coordinates:
            return nil
        }
    }

    /// The one way to train that leads the hub: what waits for the player
    /// today (the Daily 5 still open, then the mistakes due), and puzzles
    /// when nothing does or for a guest.
    static func lead(_ state: TrainState?) -> TrainRow {
        guard let state else { return .puzzles }
        if let daily = state.daily, !daily.doneToday { return .daily }
        if let mistakes = state.mistakes, mistakes.due > 0 { return .mistakes }
        return .puzzles
    }

    /// The lead, said as today's work: a line above the name, the number
    /// that matters with what it counts, and the action.
    func leadCopy(_ state: TrainState?) -> (eyebrow: String, metric: (value: String, caption: String)?, action: String) {
        switch self {
        case .daily:
            let streak = state?.daily?.streak.current ?? 0
            return ("Open today", streak > 0 ? (CDFormat.count(streak), "day streak") : nil, "Start today's five")
        case .mistakes:
            let due = state?.mistakes?.due ?? 0
            return ("Due today", (CDFormat.count(due), due == 1 ? "position to solve" : "positions to solve"), "Practise")
        default:
            // A guest has the free set; a player is rated.
            return (state == nil ? "Free to start" : "Rated", state?.puzzleRating.map { (CDFormat.count($0), "puzzle rating") }, "Solve puzzles")
        }
    }
}

/// "Train": the ways to practise. One of them leads, framed as the plate of
/// the screen: what waits for the player today. The others follow as the
/// chapters of a book, each under its emblem, with its figure when the
/// server gave one. A row that needs an account says so to a guest, and
/// opens a screen that offers one.
struct TrainHubView: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var home
    @State private var state: TrainState?

    var body: some View {
        let lead = TrainRow.lead(state)
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("Train")
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("A few minutes a day, on the positions that teach you most.")
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                leadPlate(lead)
                VStack(spacing: 0) {
                    let rest = TrainRow.allCases.filter { $0 != lead }
                    ForEach(Array(rest.enumerated()), id: \.element) { index, row in
                        if index > 0 { CDHairline().padding(.leading, CD.Space.s16 + 40 + CD.Space.s12) }
                        entry(row, style: CDPressStyle()) {
                            FeatureRow(
                                emblem: row.emblem,
                                title: row.title,
                                detail: row.line(isSignedIn: app.isSignedIn),
                                figure: row.figure(state)
                            )
                        }
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

    /// The plate: the emblem large, the name as a title, the number that
    /// matters, and the one primary action of the screen.
    private func leadPlate(_ row: TrainRow) -> some View {
        let copy = row.leadCopy(state)
        return VStack(alignment: .leading, spacing: CD.Space.s20) {
            HStack(alignment: .top, spacing: CD.Space.s16) {
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    Text(copy.eyebrow)
                        .cdFont(.small)
                        .foregroundStyle(CD.accentStrong)
                    Text(row.title)
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                    Text(row.summary)
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Emblem(kind: row.emblem, size: 64)
            }
            if let metric = copy.metric {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(metric.value)
                        .cdFont(.metric)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                    Text(metric.caption)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink3)
                }
                .accessibilityElement(children: .combine)
            }
            entry(row, style: .cd(.primary, size: .large, fullWidth: true)) { Text(copy.action) }
        }
        .plate()
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

    /// A way to train leads to its screen; for a guest, the two that have
    /// no screen of their own without an account lead to what an account brings.
    @ViewBuilder private func entry(_ row: TrainRow, style: some ButtonStyle, @ViewBuilder label: () -> some View) -> some View {
        switch row {
        case .puzzles:
            NavigationLink(value: AppRoute.puzzles, label: label).buttonStyle(style)
        case .woodpecker:
            NavigationLink(value: AppRoute.woodpecker, label: label).buttonStyle(style)
        case .coordinates:
            NavigationLink(value: AppRoute.coordinates, label: label).buttonStyle(style)
        case .daily:
            if app.isSignedIn {
                Button { home.open(.daily) } label: { label() }.buttonStyle(style)
            } else {
                NavigationLink {
                    TrainAccountScreen(
                        title: "Daily 5",
                        heading: "Five positions a day, from your own games",
                        message: "Each day, five positions where one of your games went wrong, and a streak that grows with the days you train. It is built from the games of an account."
                    )
                } label: { label() }
                    .buttonStyle(style)
            }
        case .mistakes:
            if app.isSignedIn {
                Button { home.open(.mistakes) } label: { label() }.buttonStyle(style)
            } else {
                NavigationLink {
                    TrainAccountScreen(
                        title: "Your mistakes",
                        heading: "Your own mistakes, until they are gone",
                        message: "Bring in your games from Chess.com or Lichess, have the engine on this phone review them, and the positions where you went wrong come back until you find the better move. It needs an account."
                    )
                } label: { label() }
                    .buttonStyle(style)
            }
        }
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
