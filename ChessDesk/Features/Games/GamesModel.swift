import Foundation
import Observation

/// The player's games on this device: the linked accounts, the list as far
/// as it has been read, and the import that fills it.
@Observable
final class GamesModel {
    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var accounts: [LinkedAccount] = []
    private(set) var games: [GameSummary] = []
    private(set) var mistakes: MistakeQueue.Counts?
    /// "Importing from Lichess: 240 games" while an import runs.
    private(set) var importing: String?
    private(set) var notice: String?
    private(set) var isLoadingMore = false
    private var nextCursor: String?

    private let app: AppModel

    init(app: AppModel) {
        self.app = app
    }

    var hasMore: Bool { nextCursor != nil }
    /// Older games remain on a game site for at least one linked account.
    var hasOlderHistory: Bool { accounts.contains { !$0.historyComplete } }

    func load() async {
        guard let token = app.token else { return }
        do {
            async let linked = app.api.accounts(token: token)
            async let page = app.api.games(cursor: nil, token: token)
            accounts = try await linked
            let first = try await page
            games = first.games
            nextCursor = first.nextCursor
            phase = .ready
            mistakes = try? await app.api.mistakes(token: token).counts
        } catch let error as APIError {
            if error.isUnauthorized { app.sessionExpired() }
            phase = .failed(error.message)
        } catch is CancellationError {
        } catch {
            phase = .failed(APIError.unreadable.message)
        }
    }

    func loadMore() async {
        guard let token = app.token, let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        guard let page = try? await app.api.games(cursor: cursor, token: token) else { return }
        games.append(contentsOf: page.games.filter { game in !games.contains { $0.id == game.id } })
        nextCursor = page.nextCursor
    }

    /// Links (or replaces) an account and brings in its recent games.
    func link(_ provider: GameProvider, username: String) async throws {
        guard let token = app.token else { return }
        let account = try await app.api.linkAccount(provider, username: username, token: token)
        accounts.removeAll { $0.provider == provider }
        accounts.append(account)
        await runImport(provider, mode: .full, chunks: 4)
    }

    func unlink(_ provider: GameProvider) async throws {
        guard let token = app.token else { return }
        try await app.api.unlinkAccount(provider, token: token)
        accounts.removeAll { $0.provider == provider }
    }

    /// New games from every linked account.
    func sync() async {
        for account in accounts { await runImport(account.provider, mode: .sync, chunks: 6) }
    }

    /// Further back in time, for the accounts whose history is not all in.
    func importOlder() async {
        for account in accounts where !account.historyComplete {
            await runImport(account.provider, mode: .history, chunks: 4)
        }
    }

    /// A game changed on its own screen (starred, reviewed): keep the row true.
    func noteReviewed(_ id: String) {
        guard let index = games.firstIndex(where: { $0.id == id }) else { return }
        let old = games[index]
        games[index] = GameSummary(
            id: old.id, source: old.source, white: old.white, black: old.black, whiteElo: old.whiteElo,
            blackElo: old.blackElo, result: old.result, timeClass: old.timeClass, timeControl: old.timeControl,
            eco: old.eco, opening: old.opening, userColor: old.userColor, playedAt: old.playedAt, ply: old.ply,
            rated: old.rated, starred: old.starred, reviewed: true
        )
        Task { [weak self] in
            guard let self, let token = app.token else { return }
            mistakes = try? await app.api.mistakes(token: token).counts
        }
    }

    func refreshMistakes() async {
        guard let token = app.token else { return }
        mistakes = try? await app.api.mistakes(token: token).counts
    }

    /// Runs up to `chunks` chunks of an import, then reads the list again. A
    /// first import is deliberately short: recent games now, the archive on demand.
    private func runImport(_ provider: GameProvider, mode: ImportMode, chunks: Int) async {
        guard let token = app.token, importing == nil else { return }
        notice = nil
        importing = "Asking \(provider.name) for your games"
        defer { importing = nil }
        var cursor: String?
        var total = 0
        do {
            for _ in 0..<chunks {
                let chunk = try await app.api.importGames(provider, mode: mode, cursor: cursor, token: token)
                total += chunk.imported
                importing = "From \(provider.name): \(CDFormat.plural(total, "game"))"
                if chunk.done || chunk.nextCursor == nil { break }
                cursor = chunk.nextCursor
            }
            if total == 0, mode == .sync { notice = "No new games on \(provider.name)." }
        } catch let error as APIError {
            notice = error.code == "provider_busy"
                ? "\(provider.name) is asking us to slow down. Try again in a minute."
                : error.message
        } catch {
            notice = APIError.unreadable.message
        }
        if let linked = try? await app.api.accounts(token: token) { accounts = linked }
        if let page = try? await app.api.games(cursor: nil, token: token) {
            games = page.games
            nextCursor = page.nextCursor
        }
    }
}

extension GameSummary {
    enum Outcome { case win, loss, draw, unknown }

    /// The result from the player's side of the board.
    var outcome: Outcome {
        switch (result, userColor) {
        case ("1/2-1/2", _): .draw
        case ("1-0", "white"), ("0-1", "black"): .win
        case ("1-0", "black"), ("0-1", "white"): .loss
        default: .unknown
        }
    }

    var opponent: String { userColor == "black" ? white : black }
    var opponentElo: Int? { userColor == "black" ? whiteElo : blackElo }

    var timeClassLabel: String {
        timeClass == "UNKNOWN" ? "" : timeClass.prefix(1) + timeClass.dropFirst().lowercased()
    }
}
