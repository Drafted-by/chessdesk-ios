import Charts
import SwiftUI

/// Today for a signed-in player (the site's `/dashboard`): the server's plan
/// for the day, the Daily 5 and its streak, the player's form and progress.
/// The plan is the screen's plate; before any game is in, the question
/// "Where do you play?" takes its place.
struct PlayerTodayView: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var navigator

    /// The home, and what is due for review when the server says.
    struct Today {
        let home: PlayerHome
        let due: DueSummary?
        let courses: [CourseCard]
    }

    var body: some View {
        Loadable(
            id: AnyHashable([AnyHashable(app.accountRevision), AnyHashable(navigator.revision)]),
            failureTitle: "Today did not load",
            load: load,
            content: { today in PlayerHomePage(home: today.home, due: today.due, courses: today.courses, reload: { navigator.refresh() }) }
        )
    }

    private func load() async throws -> Today {
        guard let token = app.token else { throw APIError.server(status: 401, code: "unauthorized", message: "Sign in to continue.") }
        // The reviews due are a bonus on this screen: without them it still works.
        async let due = try? app.api.due(token: token)
        async let courses = try? app.api.courses(token: token)
        do {
            let home = try await app.api.home(token: token)
            return Today(home: home, due: await due, courses: await courses ?? [])
        } catch let error as APIError where error.isUnauthorized {
            app.sessionExpired()
            throw error
        }
    }
}

private struct PlayerHomePage: View {
    let home: PlayerHome
    let due: DueSummary?
    let courses: [CourseCard]
    let reload: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                header
                if home.onboarding.needsWelcome {
                    WelcomeQuestion(done: reload)
                } else {
                    if let report = home.onboarding.firstReport {
                        FirstReportCard(report: report, dismissed: reload)
                    }
                    TodayPlanCard(home: home)
                    if let due, due.totalDue > 0, !DueRow.rows(due: due, courses: courses).isEmpty {
                        DueCard(due: due, courses: courses)
                    }
                    if home.totalGames > 0 {
                        FormSection(home: home)
                    }
                    if let progress = home.progress {
                        ProgressSummary(progress: progress)
                    }
                    if home.totalGames > 0 {
                        VStack(alignment: .leading, spacing: CD.Space.s12) {
                            SectionHeader(
                                title: "Last 12 weeks",
                                detail: "\(CDFormat.plural(home.pulse.activityTotal, "game")) played."
                            )
                            CDCard {
                                DayCalendar(counts: home.pulse.activity, unit: "Games played", level: Self.gameLevel)
                            }
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .refreshable { reload() }
        .debugScrollAnchor()
    }

    /// Games in a day to a shade: one, two or three, four and more.
    static func gameLevel(_ count: Int) -> Int {
        switch count {
        case 0: 0
        case 1: 1
        case 2...3: 2
        default: 3
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            TodayTopBar()
                .padding(.bottom, CD.Space.s16)
            Text(greeting)
                .cdFont(.display)
                .foregroundStyle(CD.ink)
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let words = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        guard let name = app.me?.user.name.split(separator: " ").first else { return words }
        return "\(words), \(name)"
    }

    /// The site's subtitle of the greeting, for a player.
    private var subtitle: String {
        if home.totalGames == 0 { return "Start with your own games: everything here is built from them." }
        let games = home.stats.gamesThisWeek
        return games > 0 ? "\(CDFormat.plural(games, "game")) this week. Here is what to work on next." : "Here is what to work on next."
    }
}

// MARK: The plan

/// Today's plan: the server's steps in its order, the first one leading
/// (`components/player/player-today.tsx`). Steps the app cannot open are not shown.
private struct TodayPlanCard: View {
    let home: PlayerHome

    var body: some View {
        let steps = HomeRouter.plan(home.today)
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "en_GB"))))
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
            Text(planLine(steps))
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, -CD.Space.s8)
            VStack(spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { index, planned in
                    if index > 0 { CDHairline() }
                    HomeRouteLink(route: planned.route) {
                        StepRow(number: index + 1, planned: planned)
                    }
                }
            }
            CDHairline()
            footer
        }
        .plate()
    }

    private func planLine(_ steps: [PlannedStep]) -> String {
        let minutes = steps.reduce(0) { $0 + $1.step.minutes }
        let done = home.daily.doneToday
            ? "Daily 5 done: \(home.daily.line.replacingOccurrences(of: ", done", with: "")). "
            : ""
        guard !steps.isEmpty else { return "\(done)Nothing else is waiting today." }
        return "\(done)\(CDFormat.plural(steps.count, "step")), about \(minutes) min. Start at the top."
    }

    @ViewBuilder private var footer: some View {
        if home.mistakes.total > 0 {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Mistake bank: \(CDFormat.count(home.mistakes.mastered)) of \(CDFormat.count(home.mistakes.total)) mastered")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                CDMeter(value: Double(home.mistakes.mastered) / Double(max(1, home.mistakes.total)))
                    .frame(maxWidth: 320)
                    .accessibilityLabel("Mistakes mastered")
            }
        } else {
            Text("Every game you review adds its mistakes to your drill.")
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
        }
    }
}

private struct StepRow: View {
    let number: Int
    let planned: PlannedStep

    var body: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            Text("\(number)")
                .cdFont(.meta)
                .foregroundStyle(planned.leads ? CD.accentInk : CD.ink3)
                .frame(width: 24, height: 24)
                .background(planned.leads ? CD.accent : CD.surface3, in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                Text(planned.step.title)
                    .cdFont(.bodyStrong)
                    .foregroundStyle(CD.ink)
                Text(planned.step.detail)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .lineLimit(2)
            }
            Spacer(minLength: CD.Space.s8)
            VStack(alignment: .trailing, spacing: CD.Space.s4) {
                if planned.leads {
                    HStack(spacing: CD.Space.s4) {
                        Text(planned.step.cta)
                        Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold))
                    }
                    .cdFont(.small)
                    .foregroundStyle(CD.ink)
                    .padding(.horizontal, CD.Space.s12)
                    .frame(minHeight: 32)
                    .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(CD.lineStrong, radius: CD.Radius.md)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CD.ink4)
                }
                Text("\(planned.step.minutes) min")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink4)
                    .cdNumber()
            }
        }
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(planned.step.title). \(planned.step.detail). About \(planned.step.minutes) minutes.")
        .accessibilityHint(planned.step.cta)
    }
}

// MARK: Form

/// The player's form: rating, the week, accuracy, the Daily 5 streak
/// (the site's `PlayerPulseHero`), from the figures the server computed.
private struct FormSection: View {
    let home: PlayerHome

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "Your form")
            VStack(alignment: .leading, spacing: 0) {
                if let rating = home.pulse.rating {
                    ratingBlock(rating)
                        .padding(CD.Space.s20)
                    CDHairline()
                }
                // Four figures in two rows, ruled like a score sheet.
                HStack(alignment: .top, spacing: 0) {
                    week
                    rule
                    accuracy
                }
                CDHairline()
                HStack(alignment: .top, spacing: 0) {
                    figure(
                        "Daily 5 streak", CDFormat.plural(home.daily.streak.current, "day"),
                        detail: home.daily.streak.doneToday ? "Done today" : "Open today",
                        detailTone: home.daily.streak.doneToday ? CD.ink4 : CD.accentStrong
                    )
                    rule
                    figure(
                        "Errors per game", home.stats.errorsPerGame.map { String(format: "%.1f", $0) } ?? "–",
                        detail: "Mistakes and blunders"
                    )
                }
                if let best = home.pulse.bestWin {
                    CDHairline()
                    HomeRouteLink(route: .game(id: best.gameId)) {
                        HStack(spacing: CD.Space.s12) {
                            Emblem(kind: .games, size: 36)
                            VStack(alignment: .leading, spacing: CD.Space.s2) {
                                Text("Best win").cdFont(.meta).foregroundStyle(CD.ink3)
                                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s6) {
                                    Text(best.opponent)
                                        .cdFont(.serifCard)
                                        .foregroundStyle(CD.ink)
                                        .lineLimit(1)
                                    Text(CDFormat.count(best.elo))
                                        .cdFont(.small)
                                        .foregroundStyle(CD.ink3)
                                        .cdNumber()
                                }
                            }
                            Spacer(minLength: CD.Space.s8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(CD.ink4)
                        }
                        .padding(.horizontal, CD.Space.s20)
                        .frame(minHeight: 64)
                        .contentShape(Rectangle())
                    }
                }
            }
            .cardSurface()
            .hairline()
        }
    }

    private var rule: some View {
        Rectangle().fill(CD.line).frame(width: 1)
    }

    // MARK: Rating

    /// The label, the big number and its delta, then the line with its
    /// scale: the highest and lowest rating of the period on the right, the
    /// last game marked.
    private func ratingBlock(_ rating: PlayerHome.Pulse.Rating) -> some View {
        let low = rating.series.min() ?? rating.current
        let high = rating.series.max() ?? rating.current
        let span = max(40, high - low)
        let floor = low - span / 5
        return VStack(alignment: .leading, spacing: CD.Space.s12) {
            HStack(alignment: .top, spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text("\(TimeClass.label(rating.timeClass)) rating")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                    HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                        Text(CDFormat.count(rating.current))
                            .cdFont(.metric)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        if let delta = rating.delta, delta != 0 {
                            DeltaText(value: delta, suffix: "in 30 days")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                Spacer(minLength: CD.Space.s8)
                Emblem(kind: .insights, size: 44)
            }
            if rating.series.count > 1 {
                Chart {
                    ForEach(Array(rating.series.enumerated()), id: \.offset) { index, value in
                        AreaMark(x: .value("Game", index), yStart: .value("Floor", floor), yEnd: .value("Rating", value))
                            .foregroundStyle(
                                LinearGradient(colors: [CD.accent.opacity(0.22), CD.accent.opacity(0)], startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Game", index), y: .value("Rating", value))
                            .foregroundStyle(CD.accent)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.monotone)
                    }
                    PointMark(x: .value("Game", rating.series.count - 1), y: .value("Rating", rating.series[rating.series.count - 1]))
                        .foregroundStyle(CD.accentStrong)
                        .symbolSize(48)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [low, high]) { mark in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [2, 3])).foregroundStyle(CD.lineStrong)
                        AxisValueLabel {
                            // "1,342", as ratings are written everywhere else.
                            if let value = mark.as(Int.self) {
                                Text(CDFormat.count(value))
                                    .font(CDFont.meta.font)
                                    .foregroundStyle(CD.ink4)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .chartYScale(domain: floor...(high + span / 5))
                .frame(height: 96)
                .accessibilityLabel("Rating over the last \(rating.series.count) games, from \(low) to \(high)")
                Text("Last \(CDFormat.plural(rating.series.count, "game"))")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink4)
                    .cdNumber()
            }
        }
    }

    // MARK: Figures

    /// The week as a bar of results (won, drawn, lost), with its counts.
    private var week: some View {
        let week = home.pulse.week
        let total = week.wins + week.draws + week.losses
        return cell("This week") {
            Text(CDFormat.plural(home.stats.gamesThisWeek, "game"))
                .cdFont(.sectionTitle)
                .foregroundStyle(CD.ink)
                .cdNumber()
            if total > 0 {
                GeometryReader { proxy in
                    let width = proxy.size.width - CGFloat(max(0, [week.wins, week.draws, week.losses].filter { $0 > 0 }.count - 1)) * 2
                    HStack(spacing: 2) {
                        segment(week.wins, of: total, width: width, CD.win)
                        segment(week.draws, of: total, width: width, CD.draw)
                        segment(week.losses, of: total, width: width, CD.loss)
                    }
                }
                .frame(height: 4)
                .accessibilityHidden(true)
            }
            Text("\(week.wins) won · \(week.draws) drawn · \(week.losses) lost")
                .cdFont(.meta)
                .foregroundStyle(CD.ink4)
                .cdNumber()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    @ViewBuilder private func segment(_ count: Int, of total: Int, width: CGFloat, _ color: Color) -> some View {
        if count > 0 {
            Capsule().fill(color).frame(width: max(4, width * CGFloat(count) / CGFloat(total)))
        }
    }

    /// The accuracy over the reviewed games, on a meter of 100.
    private var accuracy: some View {
        cell("Accuracy") {
            Text(home.stats.accuracy.map { String(format: "%.1f%%", $0) } ?? "–")
                .cdFont(.sectionTitle)
                .foregroundStyle(CD.ink)
                .cdNumber()
            if let value = home.stats.accuracy {
                CDMeter(value: value / 100)
            }
            Text("\(CDFormat.plural(home.stats.reviewedGames, "game")) reviewed")
                .cdFont(.meta)
                .foregroundStyle(CD.ink4)
                .cdNumber()
        }
    }

    private func figure(_ label: String, _ value: String, detail: String, detailTone: Color = CD.ink4) -> some View {
        cell(label) {
            Text(value).cdFont(.sectionTitle).foregroundStyle(CD.ink).cdNumber()
            Text(detail).cdFont(.meta).foregroundStyle(detailTone).cdNumber()
        }
    }

    private func cell(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            Text(label).cdFont(.meta).foregroundStyle(CD.ink3)
            content()
        }
        .padding(.horizontal, CD.Space.s20)
        .padding(.vertical, CD.Space.s16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: Progress

/// Mistakes mastered, the first patterns and the goal (the site's `ProgressPanel`).
private struct ProgressSummary: View {
    let progress: HomeProgress

    @Environment(HomeNavigator.self) private var navigator

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "Progress")
                Button("All progress") { navigator.open(.progress) }
                    .cdFont(.small)
                    .tint(CD.accentStrong)
                    .frame(minHeight: 44)
            }
            CDCard(padding: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    MasteredBlock(mastered: progress.mastered, chartHeight: 100)
                    CDHairline()
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text("Patterns in your games").cdFont(.meta).foregroundStyle(CD.ink3)
                        if progress.patterns.isEmpty {
                            Text("Patterns appear after a few more reviewed games: openings where losses pile up, time trouble, hanging pieces.")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            PatternRows(patterns: Array(progress.patterns.prefix(3)))
                        }
                    }
                    if let goal = progress.goal {
                        CDHairline()
                        Button { navigator.open(.progress) } label: {
                            HStack {
                                GoalSummaryView(goal: goal)
                                Spacer(minLength: CD.Space.s8)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(CD.ink4)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
            }
        }
    }
}

// MARK: Onboarding

/// "Where do you play?", before anything else (the site's `/welcome`). Links
/// the account with the Games tab's own field; skipping is fine.
private struct WelcomeQuestion: View {
    let done: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var navigator
    @State private var games: GamesModel?
    @State private var isFinishing = false
    @State private var refused: PendingGameAccount?
    @State private var refusedMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text(app.me.map { "Welcome, \($0.user.name.split(separator: " ").first ?? "")" } ?? "Welcome to ChessDesk")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                Text("Where do you play?")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("Everything here is built from your own games. Give your username on Chess.com or Lichess: your public games come in, and no password is asked.")
                    .cdFont(.ledeSmall)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            OrnamentRule()
            if let games {
                ForEach(GameProvider.allCases) { provider in
                    LinkAccountField(
                        provider: provider, model: games,
                        prefill: refused?.provider == provider ? refused?.username : nil,
                        prefillError: refused?.provider == provider ? refusedMessage : nil
                    )
                    .id(refused?.provider == provider ? "refused" : provider.rawValue)
                }
                if let importing = games.importing {
                    HStack(spacing: CD.Space.s12) {
                        ProgressView().tint(CD.ink3)
                        Text(importing).cdFont(.small).foregroundStyle(CD.ink2).cdNumber()
                    }
                }
            }
            Button("Skip for now") { finish() }
                .buttonStyle(.cd(.ghost, fullWidth: true))
                .disabled(isFinishing || games?.importing != nil)
            CDHairline()
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Text("New to chess, or no online games yet?")
                    .cdFont(.cardTitle)
                    .foregroundStyle(CD.ink)
                Text("Reach 1000 Elo is the course for players who know the moves and still lose. Its first stages are free, and it needs no games.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Start Reach 1000 Elo") {
                    finish(reloads: false)
                    navigator.open(.path(slug: FeaturedPath.slug))
                }
                .buttonStyle(.cd(.secondary, fullWidth: true))
            }
        }
        .plate()
        .task {
            guard games == nil else { return }
            let model = GamesModel(app: app)
            games = model
            // The username given on first launch, before the account existed:
            // linked now, once. Refused (a typo), it comes back in its field.
            guard let pending = PendingGameAccount.load() else { return }
            PendingGameAccount.clear()
            do {
                try await model.link(pending.provider, username: pending.username)
            } catch {
                refusedMessage = (error as? APIError)?.code == "not_found"
                    ? "No \(pending.provider.name) player has this username."
                    : (error as? APIError)?.message ?? APIError.unreadable.message
                refused = pending
            }
        }
        // A linked account answers the question; its games keep coming in.
        .onChange(of: games?.accounts.count ?? 0) { _, count in
            if count > 0, games?.importing == nil { finish() }
        }
        .onChange(of: games?.importing == nil) { _, idle in
            if idle, (games?.accounts.count ?? 0) > 0 { finish() }
        }
    }

    private func finish(reloads: Bool = true) {
        guard !isFinishing, let token = app.token else { return }
        isFinishing = true
        Task {
            try? await app.api.completeOnboarding(token: token)
            isFinishing = false
            if reloads { done() }
        }
    }
}

/// The first report, once the newest games are reviewed (the site's `HomeReport`).
private struct FirstReportCard: View {
    let report: PlayerHome.Onboarding.FirstReport
    let dismissed: () -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                HStack(alignment: .top, spacing: CD.Space.s12) {
                    Emblem(kind: .review, size: 44, surface: CD.surface2)
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text("Your first report")
                            .cdFont(.plateTitle)
                            .foregroundStyle(CD.ink)
                        Text(source)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: dismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(CD.ink3)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Dismiss the report")
                    .padding(.top, -CD.Space.s12)
                    .padding(.trailing, -CD.Space.s12)
                }
                Grid(alignment: .leading, horizontalSpacing: CD.Space.s16, verticalSpacing: CD.Space.s12) {
                    GridRow {
                        cell("Accuracy", report.accuracy.map { String(format: "%.1f%%", $0) } ?? "–",
                             "Average over \(CDFormat.plural(report.reviewedGames, "game"))")
                        if let opening = report.opening {
                            cell("Most played opening", opening.name,
                                 "\(opening.wins) won · \(opening.draws) drawn · \(opening.losses) lost")
                        }
                    }
                }
                if let blunder = report.blunder {
                    CDHairline()
                    HStack(alignment: .top, spacing: CD.Space.s12) {
                    MoveSeal(.blunder, size: 26)
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text("Costliest move").cdFont(.meta).foregroundStyle(CD.ink3)
                        Text("\(blunder.moveLabel)\(blunder.moveLabel.hasSuffix("…") ? "" : " ")\(blunder.san)\(blunder.winLoss > 0 ? String(format: ", −%.0f%% win chance", blunder.winLoss) : "")")
                            .cdFont(.bodyStrong)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        Text("Best was \(blunder.bestSan) · vs \(blunder.opponent)")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                    }
                    }
                    .accessibilityElement(children: .combine)
                    CDHairline()
                }
                if !report.pendingGameIds.isEmpty {
                    Text("\(CDFormat.plural(report.pendingGameIds.count, "game")) of this batch still to review: open them in Games.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: CD.Space.s12) {
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text(report.drillPositions > 0 ? CDFormat.plural(report.drillPositions, "position") + " to drill" : "Nothing to drill yet")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        Text(report.drillPositions > 0 ? "Each comes back until you find the better move." : "Review a game to fill your drill.")
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: CD.Space.s8)
                    if report.drillPositions > 0 {
                        HomeRouteLink(route: .mistakes) {
                            Text("Start the drill")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink)
                                .padding(.horizontal, CD.Space.s12)
                                .frame(minHeight: 44)
                                .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                                .hairline(CD.lineStrong, radius: CD.Radius.md)
                        }
                    }
                }
            }
        }
    }

    private var source: String {
        let site = report.provider?.value.map { " on \($0.name)" } ?? ""
        return "From your \(CDFormat.plural(report.reviewedGames, "newest game", "newest games"))\(site)."
    }

    private func cell(_ label: String, _ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s2) {
            Text(label).cdFont(.meta).foregroundStyle(CD.ink3)
            Text(value).cdFont(.cardTitle).foregroundStyle(CD.ink).cdNumber().lineLimit(2)
            Text(detail).cdFont(.meta).foregroundStyle(CD.ink4).cdNumber()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func dismiss() {
        guard let token = app.token else { return }
        Task {
            try? await app.api.dismissFirstReport(token: token)
            dismissed()
        }
    }
}
