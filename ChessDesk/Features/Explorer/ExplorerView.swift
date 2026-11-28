import ChessCore
import SwiftUI

/// The opening explorer of the player's own games: pick a colour, walk the
/// tree of positions the games reached, see how each move scored, and open
/// a game that got there. A working screen: a board, rows, no ornament.
struct ExplorerView: View {
    @Environment(AppModel.self) private var app
    @State private var model: ExplorerModel?
    @State private var signIn: SignInView.Mode?
    @State private var loadedRevision: Int?

    var body: some View {
        Group {
            if app.playerToken == nil {
                guest
            } else if let model {
                switch model.phase {
                case .loading:
                    LoadingView()
                case let .failed(message):
                    LoadFailureView(title: "The explorer did not load", message: message) {
                        Task { await model.load() }
                    }
                case .ready:
                    ExplorerContent(model: model)
                }
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Explorer")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .task(id: app.accountRevision) {
            guard let token = app.playerToken else {
                model = nil
                return
            }
            // Back from a game: the walk and the filters are kept.
            if model != nil, loadedRevision == app.accountRevision { return }
            loadedRevision = app.accountRevision
            let fresh = ExplorerModel(api: app.api, token: token, onUnauthorized: { app.sessionExpired() })
            #if DEBUG
                await ExplorerDebug.prepare(fresh)
            #else
                await fresh.load()
            #endif
            model = fresh
        }
        .sheet(item: $signIn) { SignInView(mode: $0) }
    }

    private var guest: some View {
        ScrollView {
            CDCard(tone: .raised, padding: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Your openings, from your own games")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("All your games merged into one tree of moves: how often you play each one and how you score with it. It reads the games of an account.")
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
            .explorerPage()
        }
    }
}

private extension View {
    func explorerPage() -> some View {
        pageGutter()
            .padding(.top, CD.Space.s12)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}

private struct ExplorerContent: View {
    @Bindable var model: ExplorerModel

    @State private var showsFilters = false
    @State private var opened: GameRoute?

    var body: some View {
        ScrollView {
            if let summary = model.summary, summary.isEmpty {
                onboarding(summary).explorerPage()
            } else {
                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    controls
                    status
                    if let summary = model.summary, summary.capped, let limit = summary.limit {
                        capped(explored: limit, imported: summary.imported)
                    }
                    if let position = model.position {
                        board(position)
                        ExplorerLine(model: model)
                        if model.path.isEmpty, model.isCurrent { insights(position.insights) }
                        moves(position)
                        games(position)
                    } else if let failure = model.positionFailure {
                        failed(failure)
                    } else {
                        ProgressView().tint(CD.ink3).frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .explorerPage()
            }
        }
        .sheet(isPresented: $showsFilters) { ExplorerFiltersSheet(model: model) }
        .sheet(isPresented: $model.showsPremium) { PremiumSheet() }
        // Pushed from state, not from a value link: the screen works wherever
        // it is hung, in a stack with a path or without.
        .navigationDestination(item: $opened) { route in
            switch route {
            case let .game(id): GameScreen(id: id)
            }
        }
        #if DEBUG
            .onAppear { if ExplorerDebug.opensFilters { showsFilters = true } }
        #endif
    }

    // MARK: Colour and filters

    private var controls: some View {
        HStack(spacing: CD.Space.s8) {
            CDSegmented(
                options: [
                    (value: Side.white, label: "White \(CDFormat.count(model.games(as: .white)))"),
                    (value: Side.black, label: "Black \(CDFormat.count(model.games(as: .black)))"),
                ],
                selection: Binding(get: { model.side }, set: { model.choose(side: $0) })
            )
            Button {
                showsFilters = true
            } label: {
                HStack(spacing: CD.Space.s6) {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 14, weight: .medium))
                    Text("Filters")
                    if model.filters.activeCount > 0 {
                        Text(String(model.filters.activeCount))
                            .font(.custom("Geist-SemiBold", size: 11.5, relativeTo: .caption))
                            .foregroundStyle(CD.accentInk)
                            .cdNumber()
                            .frame(minWidth: 18, minHeight: 18)
                            .background(CD.accent, in: RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous))
                    }
                }
            }
            .buttonStyle(.cd(.secondary))
            .accessibilityLabel(model.filters.activeCount > 0 ? "Filters, \(model.filters.activeCount) on" : "Filters")
        }
    }

    /// One sentence on what is being looked at, as on the site.
    @ViewBuilder private var status: some View {
        if let position = model.position, model.positionFailure == nil {
            let sideName = model.side == .white ? "White" : "Black"
            let filtered = model.filters.activeCount > 0
            if position.total == 0 {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("No games as \(sideName)\(filtered ? " with these filters" : "").")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink2)
                    HStack(spacing: CD.Space.s8) {
                        if filtered {
                            Button("Clear filters") { model.clearFilters() }.buttonStyle(.cd(.secondary, size: .small))
                        }
                        Button("Show my games as \(model.side == .white ? "Black" : "White")") {
                            model.choose(side: model.side.opposite)
                        }
                        .buttonStyle(.cd(.secondary, size: .small))
                    }
                }
            } else {
                Text(
                    model.path.isEmpty
                        ? "\(CDFormat.plural(position.total, "game")) as \(sideName)\(filtered ? " with these filters" : ""). Tap a move to walk down your tree."
                        : "\(CDFormat.count(position.reaching)) of your games reached this position."
                )
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
                .cdNumber()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func capped(explored: Int, imported: Int) -> some View {
        let locked = max(0, imported - explored)
        return CDCard {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                HStack(spacing: CD.Space.s8) {
                    CDBadge(text: "Premium", tone: .premium)
                    Text("Your \(CDFormat.count(explored)) most recent games")
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                }
                Text("\(CDFormat.count(locked)) older \(locked == 1 ? "game is" : "games are") not in this tree. Premium adds every game you have imported, so rare lines and old habits show up too.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .fixedSize(horizontal: false, vertical: true)
                Button("See Premium") { model.showsPremium = true }
                    .buttonStyle(.cd(.secondary, size: .small))
            }
        }
    }

    // MARK: Board

    private func board(_ position: ExplorerPosition) -> some View {
        let shown = Position(fen: position.fen) ?? .start
        // One arrow: the move played most from here.
        let most = position.moves.first?.uci.flatMap { Move(uci: $0) }.map { shown.normalized($0) }
        return BoardView(
            position: shown,
            orientation: model.side,
            arrows: most.map { [BoardArrow(from: $0.from, to: $0.to, brush: .move)] } ?? [],
            movableSide: nil
        )
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
        .opacity(model.isCurrent ? 1 : 0.7)
        .animation(CD.Motion.state, value: model.isCurrent)
    }

    // MARK: Where to look first

    @ViewBuilder private func insights(_ insights: ExplorerPosition.Insights) -> some View {
        let cards: [(title: String, line: ExplorerPosition.Insight)] = [
            insights.mostPlayed.map { ("Main line", $0) },
            insights.best.map { ("Best line", $0) },
            insights.leak.map { ("Biggest leak", $0) },
        ].compactMap { $0 }
        if !cards.isEmpty {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                SectionHeader(title: "Where to look first")
                VStack(spacing: 0) {
                    ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                        if index > 0 { CDHairline() }
                        Button {
                            model.go(to: card.line.path)
                        } label: {
                            HStack(spacing: CD.Space.s12) {
                                VStack(alignment: .leading, spacing: CD.Space.s2) {
                                    Text(card.title).cdFont(.meta).foregroundStyle(CD.ink3)
                                    Text(card.line.line)
                                        .cdFont(.san)
                                        .foregroundStyle(CD.ink)
                                        .cdNumber()
                                        .lineLimit(1)
                                }
                                Spacer(minLength: CD.Space.s8)
                                VStack(alignment: .trailing, spacing: CD.Space.s2) {
                                    let percent = Int((card.line.score * 100).rounded())
                                    Text("\(percent)%")
                                        .cdFont(.cardTitle)
                                        .foregroundStyle(card.line.score >= 0.55 ? CD.win : card.line.score <= 0.45 ? CD.loss : CD.ink)
                                        .cdNumber()
                                    Text(CDFormat.plural(card.line.games, "game"))
                                        .cdFont(.meta)
                                        .foregroundStyle(CD.ink3)
                                        .cdNumber()
                                }
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(CD.ink4)
                            }
                            .padding(.horizontal, CD.Space.s16)
                            .frame(minHeight: 60)
                            .contentShape(Rectangle())
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(card.title): \(card.line.line), \(Int((card.line.score * 100).rounded())) percent over \(CDFormat.plural(card.line.games, "game"))")
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
                .cardSurface()
                .hairline()
            }
        }
    }

    // MARK: Moves

    @ViewBuilder private func moves(_ position: ExplorerPosition) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s8) {
            SectionHeader(title: model.sideToMove == model.side ? "What you played" : "What your opponents played")
            if position.moves.isEmpty {
                CDCard {
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text(emptyTitle(position)).cdFont(.cardTitle).foregroundStyle(CD.ink)
                        Text(emptyDetail(position))
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(position.moves.enumerated()), id: \.element.san) { index, move in
                        if index > 0 { CDHairline() }
                        ExplorerMoveRow(move: move, isTop: index == 0, canWalk: !position.endOfData) {
                            model.push(move.san)
                        }
                    }
                }
                .cardSurface()
                .hairline()
                .opacity(model.isCurrent ? 1 : 0.55)
                .allowsHitTesting(model.isCurrent)
                if position.endOfData {
                    Text("End of opening data. ChessDesk tracks the first 20 moves of each game.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                }
            }
        }
    }

    private func emptyTitle(_ position: ExplorerPosition) -> String {
        if position.endOfData { return "End of opening data" }
        return position.reaching == 0 ? "No games reach this position" : "The opening moves end here"
    }

    private func emptyDetail(_ position: ExplorerPosition) -> String {
        if position.endOfData { return "ChessDesk tracks the first 20 moves of each game." }
        return position.reaching == 0
            ? "Loosen the filters or step back a move to see what was played."
            : "No further move is recorded for these games. Open one below to see how it went on."
    }

    // MARK: Games

    @ViewBuilder private func games(_ position: ExplorerPosition) -> some View {
        if !position.games.isEmpty {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                SectionHeader(
                    title: model.path.isEmpty ? "Latest games" : "Games that reached this position",
                    detail: position.reaching > position.games.count
                        ? "The \(CDFormat.count(position.games.count)) most recent of \(CDFormat.count(position.reaching))." : nil
                )
                VStack(spacing: 0) {
                    ForEach(Array(position.games.enumerated()), id: \.element.id) { index, game in
                        if index > 0 { CDHairline() }
                        Button {
                            opened = .game(id: game.id)
                        } label: {
                            ExplorerGameRow(game: game)
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
                .cardSurface()
                .hairline()
            }
        }
    }

    private func failed(_ message: String) -> some View {
        CDCard {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text(message).cdFont(.body).foregroundStyle(CD.ink2).fixedSize(horizontal: false, vertical: true)
                Button("Try again") { model.retry() }.buttonStyle(.cd(.secondary))
            }
        }
    }

    /// Nothing to explore yet: what the screen does, and where the games come from.
    private func onboarding(_ summary: ExplorerSummary) -> some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Bring in your games first")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text("The explorer merges every game you played with one colour into a tree of moves. Each move shows how often you met it and how you scored.")
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    summary.hasLinkedAccount
                        ? "Your account is linked, but no game with opening moves is in yet. Pull down in Games to bring in your latest games."
                        : "Give your Chess.com or Lichess username in Games: your public games come in, no password is asked."
                )
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
                if let limit = summary.limit {
                    Text("The free plan explores your \(CDFormat.count(limit)) most recent games. Games against ChessDesk bots are not counted.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The line walked so far, with a way back: one row that follows the last move.
private struct ExplorerLine: View {
    let model: ExplorerModel

    var body: some View {
        HStack(spacing: CD.Space.s8) {
            Button {
                model.back()
            } label: {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(model.canGoBack ? CD.ink : CD.ink4)
                    .frame(width: 44, height: 44)
                    .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(CD.lineStrong, radius: CD.Radius.md)
            }
            .buttonStyle(CDPressStyle())
            .disabled(!model.canGoBack)
            .accessibilityLabel("Back one move")
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        if model.path.isEmpty {
                            Text("Start position")
                                .cdFont(.small)
                                .foregroundStyle(CD.ink3)
                                .padding(.horizontal, CD.Space.s8)
                        }
                        ForEach(Array(model.path.enumerated()), id: \.offset) { index, san in
                            if index.isMultiple(of: 2) {
                                Text("\(index / 2 + 1).")
                                    .cdFont(.meta)
                                    .foregroundStyle(CD.ink4)
                                    .cdNumber()
                                    .padding(.leading, CD.Space.s6)
                                    .accessibilityHidden(true)
                            }
                            let isLast = index == model.path.count - 1
                            Button {
                                model.cut(to: index + 1)
                            } label: {
                                Text(san)
                                    .cdFont(.san)
                                    .foregroundStyle(isLast ? CD.ink : CD.ink2)
                                    .padding(.horizontal, 7)
                                    .frame(height: 30)
                                    .background(
                                        isLast ? CD.accentSoft : .clear,
                                        in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous)
                                            .strokeBorder(isLast ? CD.accentLine : .clear, lineWidth: 1)
                                    )
                                    .frame(minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(CDPressStyle())
                            .id(index)
                            .accessibilityAddTraits(isLast ? .isSelected : [])
                        }
                        HStack(spacing: CD.Space.s6) {
                            SideSwatch(side: model.sideToMove)
                            Text("\(model.sideToMove == .white ? "White" : "Black") to move")
                                .cdFont(.meta)
                                .foregroundStyle(CD.ink3)
                        }
                        .padding(.leading, CD.Space.s8)
                        .id(-1)
                    }
                    .padding(.horizontal, CD.Space.s8)
                }
                .frame(height: 44)
                .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                .hairline(radius: CD.Radius.md)
                .onChange(of: model.path, initial: true) { _, _ in
                    withAnimation(CD.Motion.state) { reader.scrollTo(-1, anchor: .trailing) }
                }
            }
        }
    }
}

/// One move played from the position: how many games, how they ended, the score.
private struct ExplorerMoveRow: View {
    let move: ExplorerPosition.Move
    let isTop: Bool
    let canWalk: Bool
    let walk: () -> Void

    var body: some View {
        Button(action: walk) {
            HStack(spacing: CD.Space.s12) {
                HStack(spacing: CD.Space.s6) {
                    Circle().fill(isTop ? CD.accent : .clear).frame(width: 5, height: 5)
                    Text(move.san).cdFont(.san).foregroundStyle(CD.ink)
                }
                .frame(width: 68, alignment: .leading)
                Text(CDFormat.count(move.games))
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
                    .frame(width: 34, alignment: .trailing)
                ExplorerResultBar(wins: move.wins, draws: move.draws, losses: move.losses)
                Text("\(move.percent)%")
                    .cdFont(.cardTitle)
                    .foregroundStyle(move.tone == .good ? CD.win : move.tone == .even ? CD.ink2 : CD.loss)
                    .cdNumber()
                    .frame(width: 44, alignment: .trailing)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(canWalk ? CD.ink4 : .clear)
            }
            .padding(.horizontal, CD.Space.s16)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(move.san), played \(CDFormat.plural(move.games, "time")), \(move.percent) percent score")
        }
        .buttonStyle(CDPressStyle())
        .disabled(!canWalk)
    }
}

/// Wins, draws and losses with their counts, as the site's result bar
/// (`lib/explorer/result-bar.ts`: the draw count shows from 9% of the bar).
private struct ExplorerResultBar: View {
    let wins: Int
    let draws: Int
    let losses: Int

    var body: some View {
        GeometryReader { proxy in
            let total = CGFloat(max(1, wins + draws + losses))
            let width = proxy.size.width
            HStack(spacing: 0) {
                segment(wins, CD.win, CD.accentInk, width: width * CGFloat(wins) / total)
                segment(
                    draws, CD.surface4, CD.ink2, width: width * CGFloat(draws) / total,
                    shows: CGFloat(draws) / total >= 0.09
                )
                segment(losses, CD.loss, CD.accentInk, width: width * CGFloat(losses) / total)
            }
        }
        .frame(height: 18)
        .background(CD.surface3)
        .clipShape(RoundedRectangle(cornerRadius: CD.Radius.xs, style: .continuous))
        .accessibilityHidden(true)
    }

    private func segment(_ count: Int, _ fill: Color, _ ink: Color, width: CGFloat, shows: Bool = true) -> some View {
        ZStack {
            Rectangle().fill(fill)
            if shows, width >= 14 {
                Text(String(count))
                    .font(.custom("Geist-SemiBold", fixedSize: 11.5))
                    .foregroundStyle(ink)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .frame(width: max(0, width))
    }
}

private struct ExplorerGameRow: View {
    let game: GameSummary

    var body: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            mark
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                HStack(spacing: CD.Space.s6) {
                    Text(game.opponent)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    if let elo = game.opponentElo {
                        Text(String(elo)).cdFont(.small).foregroundStyle(CD.ink3).cdNumber()
                    }
                }
                Text(detail)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: CD.Space.s8)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .padding(.horizontal, CD.Space.s16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mark.word) against \(game.opponent), \(detail)")
    }

    private var mark: ResultMark {
        let outcome: ResultMark.Outcome = switch game.outcome {
        case .win: .win
        case .loss: .loss
        case .draw: .draw
        case .unknown: .unknown
        }
        return ResultMark(outcome: outcome, side: game.userColor == "white" ? .white : game.userColor == "black" ? .black : nil)
    }

    private var detail: String {
        let day = game.playedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_US")))
        return [game.timeClassLabel, game.opening, day].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}
