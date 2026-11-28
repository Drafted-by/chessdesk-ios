import ChessCore
import SwiftUI

/// "Games against your repertoire": the player's latest games with the
/// repertoire's colour, each checked move by move by the server, with the
/// move where the game left the preparation. Premium.
struct RepertoireAdherenceScreen: View {
    let id: String
    let name: String
    let side: Side

    @Environment(AppModel.self) private var app
    @State private var phase: Phase = .loading
    @State private var showsPremium = false
    @State private var opened: GameRoute?

    private enum Phase {
        case loading
        case loaded(RepertoireAdherence)
        case premiumRequired(String)
        case failed(String)
    }

    private var sideName: String { side == .white ? "White" : "Black" }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                LoadingView()
            case let .failed(message):
                LoadFailureView(title: "Your games did not load", message: message) { Task { await load() } }
            case let .premiumRequired(message):
                paywall(message)
            case let .loaded(check):
                content(check)
            }
        }
        .navigationTitle("Games against your repertoire")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .cdPage()
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
        .navigationDestination(item: $opened) { route in
            switch route {
            case let .game(id): GameScreen(id: id)
            }
        }
        .task {
            // Not again on the way back from a game.
            if case .loaded = phase { return }
            await load()
        }
    }

    private func load() async {
        guard let token = app.playerToken else {
            phase = .failed("Sign in to continue.")
            return
        }
        phase = .loading
        do {
            phase = .loaded(try await app.api.repertoireAdherence(id: id, token: token))
        } catch is CancellationError {
        } catch {
            let failure = error as? APIError ?? .unreadable
            if failure.isUnauthorized { app.sessionExpired() }
            phase = failure.isPremiumRequired ? .premiumRequired(failure.message) : .failed(failure.message)
        }
    }

    private func paywall(_ message: String) -> some View {
        ScrollView {
            CDCard(tone: .raised, padding: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    CDBadge(text: "Premium", tone: .premium)
                    Text("See where your games left your preparation")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Every game you play as \(sideName) is checked against \(name), move by move: the exact move where you left it, and the replies your opponents really play.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(message)
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("See Premium") { showsPremium = true }
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .padding(.top, CD.Space.s4)
                }
            }
            .page()
        }
    }

    @ViewBuilder private func content(_ check: RepertoireAdherence) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s16) {
                if !check.hasTree {
                    message("Add some moves in the builder first. There is nothing to check games against yet.")
                } else if check.games.isEmpty {
                    message("No game as \(sideName) to check yet. Bring in your games from Chess.com or Lichess in Games: every game you play with this colour is then checked against the repertoire.")
                } else {
                    Text("Your last \(CDFormat.plural(check.games.count, "game")) as \(sideName), checked move by move against \(name).")
                        .cdFont(.body)
                        .foregroundStyle(CD.ink2)
                        .cdNumber()
                        .fixedSize(horizontal: false, vertical: true)
                    summary(check)
                    VStack(spacing: 0) {
                        ForEach(Array(check.games.enumerated()), id: \.element.id) { index, game in
                            if index > 0 { CDHairline() }
                            Button {
                                opened = .game(id: game.gameId)
                            } label: {
                                AdherenceRow(game: game)
                            }
                            .buttonStyle(CDPressStyle())
                        }
                    }
                    .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
                    .hairline()
                }
            }
            .page()
        }
    }

    private func message(_ text: String) -> some View {
        CDCard {
            Text(text)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Followed, left early, and the rest, as one figure and one bar.
    private func summary(_ check: RepertoireAdherence) -> some View {
        let total = check.games.count
        let other = max(0, total - check.followed - check.deviated)
        return CDCard(tone: .raised) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(CDFormat.count(check.followed))
                        .cdFont(.metricMedium)
                        .foregroundStyle(CD.ink)
                        .cdNumber()
                    Text("of \(CDFormat.count(total)) stayed on the repertoire")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .cdNumber()
                }
                GeometryReader { proxy in
                    let unit = proxy.size.width / CGFloat(max(1, total))
                    HStack(spacing: 2) {
                        if check.followed > 0 { Rectangle().fill(CD.accent).frame(width: unit * CGFloat(check.followed)) }
                        if check.deviated > 0 { Rectangle().fill(CD.loss).frame(width: unit * CGFloat(check.deviated)) }
                        Rectangle().fill(CD.surface4)
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: CD.Space.s4) {
                    legend(CD.accent, "\(CDFormat.count(check.followed)) followed")
                    legend(CD.loss, "\(CDFormat.count(check.deviated)) left early")
                    legend(CD.surface4, "\(CDFormat.count(other)) out of book or never reached")
                }
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: CD.Space.s8) {
            RoundedRectangle(cornerRadius: 2, style: .continuous).fill(color).frame(width: 8, height: 8)
            Text(text).cdFont(.meta).foregroundStyle(CD.ink3).cdNumber()
        }
    }
}

private extension View {
    func page() -> some View {
        pageGutter()
            .padding(.top, CD.Space.s16)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
    }
}

private struct AdherenceRow: View {
    let game: RepertoireAdherence.Game

    var body: some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            Text(mark.letter)
                .font(.custom("Geist-SemiBold", size: 12.5, relativeTo: .caption))
                .foregroundStyle(mark.color)
                .frame(width: 26, height: 26)
                .background(mark.color.opacity(0.14), in: RoundedRectangle(cornerRadius: CD.Radius.sm, style: .continuous))
            VStack(alignment: .leading, spacing: CD.Space.s4) {
                HStack(alignment: .firstTextBaseline, spacing: CD.Space.s8) {
                    Text(game.opponent.isEmpty ? "?" : game.opponent)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                        .lineLimit(1)
                    Text(game.playedAt.formatted(.relative(presentation: .named).locale(Locale(identifier: "en_US"))))
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .lineLimit(1)
                }
                Text(verdict.text)
                    .cdFont(.small)
                    .foregroundStyle(verdict.color)
                    .cdNumber()
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: CD.Space.s4)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CD.ink4)
        }
        .padding(.horizontal, CD.Space.s16)
        .padding(.vertical, CD.Space.s12)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(mark.word) against \(game.opponent). \(verdict.text)")
    }

    private var mark: (letter: String, word: String, color: Color) {
        switch game.result {
        case "win": ("W", "Win", CD.win)
        case "loss": ("L", "Loss", CD.loss)
        case "draw": ("D", "Draw", CD.draw)
        default: ("·", "Game", CD.ink3)
        }
    }

    /// The sentences of the site's page (`app/repertoires/[id]/games/page.tsx`).
    private var verdict: (text: String, color: Color) {
        let moves = CDFormat.plural(game.pliesFollowed, "move")
        switch game.status {
        case "deviated":
            guard let deviation = game.deviation else { return ("Left the repertoire", CD.loss) }
            let expected = deviation.expected.joined(separator: " / ")
            return ("Left at move \(deviation.moveNumber): played \(deviation.played), repertoire says \(expected)", CD.loss)
        case "followed":
            return ("Followed the repertoire (\(moves))", CD.win)
        case "out_of_book":
            return ("Left book after \(moves) (opponent deviated)", CD.ink3)
        default:
            return ("Never reached the repertoire", CD.ink3)
        }
    }
}
