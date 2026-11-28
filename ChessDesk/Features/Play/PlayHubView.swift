import ChessCore
import SwiftUI

/// The Play tab, "Play a bot": the catalogue of opponents, with the game in
/// progress on top when there is one. This is where the bots' character shows; the game
/// itself is a plain board.
struct PlayHubView: View {
    @Environment(AppModel.self) private var app
    @State private var model: PlayModel?
    @State private var filter = "all"
    @State private var pick: OpponentPick?
    @State private var open: OpenGame?
    @State private var review: String?

    /// A game on its way to the screen.
    private struct OpenGame: Identifiable, Hashable {
        let model: BotGameModel
        var id: ObjectIdentifier { ObjectIdentifier(model) }

        static func == (lhs: OpenGame, rhs: OpenGame) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    var body: some View {
        Group {
            if let model {
                switch model.phase {
                case .loading: LoadingView()
                case let .failed(message):
                    LoadFailureView(title: "The bots did not load", message: message) {
                        Task { await model.retry() }
                    }
                case let .ready(catalogue): page(catalogue, model)
                }
            } else {
                LoadingView()
            }
        }
        // The first screen of the Play tab: the page carries its own title,
        // and the name is kept for the way back from a game.
        .navigationTitle("Play")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
        .task(id: AnyHashable([AnyHashable(app.backend), AnyHashable(app.accountRevision)])) {
            let current = model ?? PlayModel(app: app)
            model = current
            await current.load()
            await current.claimPendingGame()
            #if DEBUG
                await openDebugGame(current)
            #endif
        }
        .sheet(item: $pick) { pick in
            if let model {
                BotSetupSheet(pick: pick, model: model) { game in
                    self.pick = nil
                    open = OpenGame(model: game)
                }
            }
        }
        .navigationDestination(item: $open) { game in
            BotGameScreen(model: game.model)
                .onDisappear { model?.refresh() }
        }
        .navigationDestination(item: $review) { GameScreen(id: $0) }
    }

    private func page(_ catalogue: PlayCatalogue, _ model: PlayModel) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("Play a bot")
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text(lede(catalogue))
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .frame(maxWidth: CD.readingWidth, alignment: .leading)
                }

                if model.isFromCache {
                    Text("No connection: these are the bots as you last loaded them. You can still play.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .frame(maxWidth: CD.readingWidth, alignment: .leading)
                }
                if let gameID = model.claimedGameID {
                    claimedRow(gameID, model)
                }
                if let snapshot = model.resumable {
                    GameInProgressCard(snapshot: snapshot, isOpening: model.isStarting) {
                        Task { if let game = await model.resume() { open = OpenGame(model: game) } }
                    } giveUp: {
                        model.discardResumable()
                    }
                }
                if let failure = model.startFailure, pick == nil {
                    Text(failure)
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                }

                customRow(catalogue.custom)

                CDSegmented(
                    options: [("all", "All")] + catalogue.tiers.map { ($0.id, $0.label) },
                    selection: $filter
                )
                .frame(maxWidth: 520)

                ForEach(catalogue.tiers.filter { filter == "all" || $0.id == filter }) { tier in
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        SectionHeader(title: tier.label, detail: tier.blurb)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 156), spacing: CD.Space.s12, alignment: .top)],
                            spacing: CD.Space.s12
                        ) {
                            ForEach(catalogue.bots(in: tier)) { bot in
                                Button {
                                    pick = .bot(bot)
                                } label: {
                                    BotCard(bot: bot)
                                }
                                .buttonStyle(CDPressStyle())
                            }
                        }
                    }
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: CD.pageMaxWidth)
            .frame(maxWidth: .infinity)
        }
    }

    private func lede(_ catalogue: PlayCatalogue) -> String {
        let range = "from \(CDFormat.count(catalogue.custom.rating.min)) to \(CDFormat.count(catalogue.custom.rating.max))"
        // The server says whether this session may save (`canSaveGames`); a
        // catalogue kept from an earlier visit cannot speak for today's.
        let saving = !app.api.savesBotGames ? ""
            : !app.isSignedIn ? " Sign in to save your games."
            : catalogue.canSaveGames && model?.isFromCache == false ? " Every game is saved for review." : ""
        return "Human-like opponents \(range). Pick one, then a color.\(saving)"
    }

    /// "Build your own opponent": a mechanism, not a character, so it reads
    /// as a row above the roster.
    private func customRow(_ custom: CustomOpponent) -> some View {
        Button {
            pick = .custom(custom)
        } label: {
            CDCard(padding: CD.Space.s16) {
                HStack(spacing: CD.Space.s12) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(CD.ink2)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text("Build your own opponent")
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                        Text("Set the exact rating, from \(CDFormat.count(custom.rating.min)) to \(CDFormat.count(custom.rating.max)), and start from any position.")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(CD.ink4)
                }
                .frame(minHeight: 44)
            }
        }
        .buttonStyle(CDPressStyle())
    }

    /// A game finished before signing in has just been saved to the account.
    private func claimedRow(_ gameID: String, _ model: PlayModel) -> some View {
        CDCard(tone: .raised) {
            HStack(spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text("Your last game is saved")
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                    Text("It is in your games, ready to review.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                }
                Spacer(minLength: 0)
                Button("Review") {
                    model.claimedGameShown()
                    review = gameID
                }
                .buttonStyle(.cd(.secondary))
            }
        }
    }

    #if DEBUG
        /// `-CDRoute play/<bot id>` starts a game at once (`-CDPlaySide black`
        /// to take Black); with a game in progress, it opens that game.
        private func openDebugGame(_ model: PlayModel) async {
            guard open == nil, let route = DebugLaunch.route, route.first == "play", route.count > 1,
                  !PlayDebug.consumed, let catalogue = model.catalogue
            else { return }
            PlayDebug.consumed = true
            if route[1] == "resume" {
                if let game = await model.resume() { open = OpenGame(model: game) }
                return
            }
            let side: Side = UserDefaults.standard.string(forKey: "CDPlaySide") == "black" ? .black : .white
            let chosen: OpponentPick? = route[1] == catalogue.custom.id
                ? .custom(catalogue.custom)
                : catalogue.bots.first { $0.id == route[1] }.map(OpponentPick.bot)
            guard let chosen else { return }
            let setup = chosen.setup(
                rating: PlayDebug.customRating ?? catalogue.custom.rating.default, humanSide: side, start: .standard,
                engines: catalogue.engines
            )
            if let game = await model.start(setup) { open = OpenGame(model: game) }
        }
    #endif
}

/// One character of the roster: the portrait leads, then who it is.
private struct BotCard: View {
    let bot: PlayBot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BotPortrait(avatar: bot.portraitUrl, name: bot.name)
                .aspectRatio(1, contentMode: .fit)
                .overlay(alignment: .topTrailing) {
                    if bot.access != .free {
                        CDBadge(text: bot.access == .premium ? "Premium" : "Account", tone: bot.access == .premium ? .premium : .neutral)
                            .padding(CD.Space.s8)
                    }
                }
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s6) {
                    if let flag = CountryFlag.emoji(for: bot.country) {
                        Text(flag).font(.system(size: 14))
                    }
                    Text(bot.name)
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(CDFormat.count(bot.rating))
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
                Text(bot.tagline)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .lineLimit(3, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(CD.Space.s12)
        }
        .background(CD.surface1)
        .clipShape(RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
        .hairline()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(bot.name), \(bot.country), rated \(bot.rating). \(bot.tagline)")
        .accessibilityAddTraits(.isButton)
    }
}

/// The game waiting on this device.
private struct GameInProgressCard: View {
    let snapshot: BotGameSnapshot
    let isOpening: Bool
    let resume: () -> Void
    let giveUp: () -> Void

    @State private var confirmsGivingUp = false

    private var game: BotGame? { snapshot.restored() }

    var body: some View {
        CDCard(tone: .raised) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                HStack(spacing: CD.Space.s12) {
                    BotPortrait(avatar: snapshot.setup.avatar, name: snapshot.setup.botName)
                        .frame(width: 52, height: 52)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(CD.lineStrong, lineWidth: 1))
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text("Game in progress")
                            .cdFont(.meta)
                            .foregroundStyle(CD.accentStrong)
                        Text("\(snapshot.setup.botName) \(CDFormat.count(snapshot.setup.rating))")
                            .cdFont(.serifCard)
                            .foregroundStyle(CD.ink)
                            .cdNumber()
                        Text(status)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: CD.Space.s8) {
                    Button(isOpening ? "Loading opponent…" : "Resume", action: resume)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                        .disabled(isOpening)
                    Button("Give up") { confirmsGivingUp = true }
                        .buttonStyle(.cd(.ghost))
                        .confirmationDialog("Give up this game?", isPresented: $confirmsGivingUp, titleVisibility: .visible) {
                            Button("Give up the game", role: .destructive, action: giveUp)
                            Button("Keep it", role: .cancel) {}
                        } message: {
                            Text("It will not be saved.")
                        }
                }
            }
        }
    }

    private var status: String {
        guard let game else { return "" }
        let side = "You play \(game.humanSide == .white ? "White" : "Black")"
        let moves = game.moves.isEmpty ? "no move yet" : "move \(game.moves.last?.moveNumber ?? 1)"
        return "\(side) · \(moves) · \(game.humanToMove ? "your move" : "\(snapshot.setup.botName) to move")"
    }
}
