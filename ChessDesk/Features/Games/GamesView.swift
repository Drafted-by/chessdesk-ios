import SwiftUI

/// Routes of the Games stack.
enum GameRoute: Hashable {
    case game(id: String)
}

/// "Games": the player's own games from Chess.com and Lichess, each one
/// reviewable by the engine on the phone, and the mistakes to practise.
/// A working screen: lists and rows, no ornament.
struct GamesView: View {
    @Environment(AppModel.self) private var app
    @State private var model: GamesModel?
    @State private var signIn: SignInView.Mode?
    @State private var showsAccounts = false
    @State private var showsMistakes = false
    @State private var showsSample = false

    var body: some View {
        Group {
            if !app.isSignedIn {
                guest
            } else if let model {
                content(model)
            } else {
                LoadingView()
            }
        }
        .navigationTitle("Games")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
        .task(id: app.accountRevision) {
            guard app.isSignedIn else {
                model = nil
                return
            }
            let fresh = GamesModel(app: app)
            model = fresh
            await fresh.load()
        }
        .sheet(item: $signIn) { SignInView(mode: $0) }
        #if DEBUG
            .navigationDestination(isPresented: $showsSample) { SampleGameScreen() }
            .onAppear { if DebugLaunch.route == ["games", "sample"] { showsSample = true } }
        #endif
        .navigationDestination(for: GameRoute.self) { route in
            switch route {
            case let .game(id): GameScreen(id: id, onReviewed: { model?.noteReviewed(id) })
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .cdFont(.display)
            .foregroundStyle(CD.ink)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Guest

    private var guest: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                title("Games")
                CDCard(tone: .raised, padding: CD.Space.s20) {
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        Text("Review your own games")
                            .cdFont(.plateTitle)
                            .foregroundStyle(CD.ink)
                        Text("Bring in your games from Chess.com and Lichess. The engine on this phone reviews them, and your mistakes come back as positions to solve.")
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
            }
            .page()
        }
    }

    // MARK: Signed in

    @ViewBuilder private func content(_ model: GamesModel) -> some View {
        switch model.phase {
        case .loading:
            LoadingView()
        case let .failed(message):
            LoadFailureView(title: "Your games did not load", message: message) {
                Task { await model.load() }
            }
        case .ready:
            ScrollView {
                VStack(alignment: .leading, spacing: CD.Space.s24) {
                    HStack(alignment: .firstTextBaseline) {
                        title("Games")
                        Spacer()
                        if !model.accounts.isEmpty {
                            Button("Accounts") { showsAccounts = true }
                                .cdFont(.small)
                                .tint(CD.ink2)
                        }
                    }
                    if model.accounts.isEmpty {
                        LinkAccountsCard(model: model)
                    } else {
                        if let counts = model.mistakes, counts.total > 0 {
                            MistakesCard(counts: counts) { showsMistakes = true }
                        }
                        status(model)
                        list(model)
                    }
                }
                .page()
            }
            .refreshable { await model.sync() }
            .sheet(isPresented: $showsAccounts) { AccountsSheet(model: model) }
            .fullScreenCover(isPresented: $showsMistakes, onDismiss: { Task { await model.refreshMistakes() } }) {
                MistakeTrainerScreen()
            }
        }
    }

    @ViewBuilder private func status(_ model: GamesModel) -> some View {
        if let importing = model.importing {
            HStack(spacing: CD.Space.s12) {
                ProgressView().tint(CD.ink3)
                Text(importing)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                    .cdNumber()
            }
        } else if let notice = model.notice {
            Text(notice)
                .cdFont(.small)
                .foregroundStyle(CD.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func list(_ model: GamesModel) -> some View {
        if model.games.isEmpty, model.importing == nil {
            CDCard {
                Text("No games yet. Pull down to look for new ones, or check the username in Accounts.")
                    .cdFont(.body)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(Array(model.games.enumerated()), id: \.element.id) { index, game in
                    if index > 0 { CDHairline() }
                    NavigationLink(value: GameRoute.game(id: game.id)) {
                        GameRow(game: game)
                    }
                    .buttonStyle(CDPressStyle())
                    .onAppear {
                        if index == model.games.count - 5 { Task { await model.loadMore() } }
                    }
                }
            }
            .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
            .hairline()

            if model.isLoadingMore {
                ProgressView().tint(CD.ink3).frame(maxWidth: .infinity)
            } else if !model.hasMore, model.hasOlderHistory, model.importing == nil {
                Button("Bring in older games") { Task { await model.importOlder() } }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
            }
        }
    }
}

private extension View {
    func page() -> some View {
        pageGutter()
            .padding(.top, CD.Space.s24)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}

/// One game: the result from the player's side, the opponent, when and how.
private struct GameRow: View {
    let game: GameSummary

    var body: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            Text(mark.letter)
                .font(.custom("Geist-SemiBold", size: 12.5, relativeTo: .caption))
                .foregroundStyle(mark.color)
                .frame(width: 26, height: 26)
                .background(mark.color.opacity(0.14), in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                HStack(spacing: CD.Space.s6) {
                    Text(game.opponent)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    if let elo = game.opponentElo {
                        Text(String(elo))
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
                Text(detail)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .lineLimit(1)
            }
            Spacer(minLength: CD.Space.s8)
            if game.reviewed {
                Text("Reviewed")
                    .cdFont(.meta)
                    .foregroundStyle(CD.accentStrong)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .padding(.horizontal, CD.Space.s16)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mark.word) against \(game.opponent), \(detail)\(game.reviewed ? ", reviewed" : "")")
    }

    private var mark: (letter: String, word: String, color: Color) {
        switch game.outcome {
        case .win: ("W", "Win", CD.win)
        case .loss: ("L", "Loss", CD.loss)
        case .draw: ("D", "Draw", CD.draw)
        case .unknown: ("·", "Game", CD.ink3)
        }
    }

    private var detail: String {
        let day = game.playedAt.formatted(.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_US")))
        return [game.timeClassLabel, game.opening, day].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }
}

private struct MistakesCard: View {
    let counts: MistakeQueue.Counts
    let practise: () -> Void

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Your mistakes")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(CDFormat.count(counts.due))
                        .cdFont(.metric)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                    Text(counts.due == 1 ? "position to solve today" : "positions to solve today")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink3)
                }
                .accessibilityElement(children: .combine)
                Text("\(CDFormat.plural(counts.total, "position")) from your reviewed games, \(CDFormat.count(counts.mastered)) mastered.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .cdNumber()
                if counts.due > 0 {
                    Button("Practise", action: practise)
                        .buttonStyle(.cd(.primary, fullWidth: true))
                }
            }
        }
    }
}

/// The first thing a signed-in player sees here: where do you play?
private struct LinkAccountsCard: View {
    let model: GamesModel

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                VStack(alignment: .leading, spacing: CD.Space.s6) {
                    Text("Where do you play?")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                    Text("Give your username on Chess.com or Lichess. Your public games come in; no password is asked.")
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ForEach(GameProvider.allCases) { provider in
                    LinkAccountField(provider: provider, model: model)
                }
                if let importing = model.importing {
                    HStack(spacing: CD.Space.s12) {
                        ProgressView().tint(CD.ink3)
                        Text(importing).cdFont(.small).foregroundStyle(CD.ink2).cdNumber()
                    }
                }
            }
        }
    }
}

/// A username field for one game site, with its Link button.
struct LinkAccountField: View {
    let provider: GameProvider
    let model: GamesModel

    @State private var username = ""
    @State private var error: String?
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            Text("\(provider.name) username")
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
            HStack(spacing: CD.Space.s8) {
                TextField("", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit(link)
                    .cdFont(.body)
                    .foregroundStyle(CD.ink)
                    .padding(.horizontal, CD.Space.s12)
                    .frame(minHeight: 44)
                    .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                    .hairline(CD.lineStrong, radius: CD.Radius.md)
                Button(action: link) {
                    if isWorking { ProgressView().tint(CD.ink) } else { Text("Link") }
                }
                .buttonStyle(.cd(.secondary))
                .disabled(isWorking || username.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let error {
                Text(error)
                    .cdFont(.meta)
                    .foregroundStyle(CD.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func link() {
        let name = username.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await model.link(provider, username: name)
                username = ""
            } catch let failure as APIError {
                error = failure.code == "not_found" ? "No \(provider.name) player has this username." : failure.message
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}

/// Linked accounts: which ones, when they were last read, link or unlink.
private struct AccountsSheet: View {
    let model: GamesModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                Text("Your game accounts")
                    .cdFont(.pageTitle)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                ForEach(GameProvider.allCases) { provider in
                    if let account = model.accounts.first(where: { $0.provider == provider }) {
                        linked(account)
                    } else {
                        CDCard { LinkAccountField(provider: provider, model: model) }
                    }
                }
                if let importing = model.importing {
                    HStack(spacing: CD.Space.s12) {
                        ProgressView().tint(CD.ink3)
                        Text(importing).cdFont(.small).foregroundStyle(CD.ink2).cdNumber()
                    }
                }
                Button("Done") { dismiss() }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
            }
            .padding(.horizontal, CD.Space.s24)
            .padding(.top, CD.Space.s40)
            .padding(.bottom, CD.Space.s32)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private func linked(_ account: LinkedAccount) -> some View {
        CDCard {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text(account.provider.name)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                        Text(account.username)
                            .cdFont(.cardTitle)
                            .foregroundStyle(CD.ink)
                    }
                    Spacer()
                    Button("Unlink") { Task { try? await model.unlink(account.provider) } }
                        .cdFont(.small)
                        .tint(CD.loss)
                }
                Text(synced(account))
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func synced(_ account: LinkedAccount) -> String {
        let history = account.historyComplete ? "All your games are in." : "Recent games are in; older ones on request."
        guard let date = account.lastSyncedAt else { return history }
        let when = date.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US")))
        return "Last checked \(when). \(history) Unlinking keeps the games already here."
    }
}
