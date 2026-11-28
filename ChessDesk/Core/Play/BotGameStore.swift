import Foundation

/// A finished game waiting for an account, as the site keeps one in the
/// browser (`lib/play/pending-game.ts`): a guest who creates an account or
/// signs in finds the game saved there. It waits for a week at most.
nonisolated struct PendingBotGame: Codable, Hashable, Sendable {
    static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    var request: SaveBotGameRequest
    var savedAt = Date.now

    func isFresh(at now: Date = .now) -> Bool {
        let age = now.timeIntervalSince(savedAt)
        return age >= 0 && age <= Self.maxAge
    }
}

/// The bot games kept on this device: the one being played, so it survives
/// leaving the screen and relaunching the app, and the finished one that
/// waits for an account.
nonisolated struct BotGameStore: Sendable {
    let folder: URL

    static var standard: BotGameStore {
        BotGameStore(folder: URL.applicationSupportDirectory.appending(path: "ChessDesk", directoryHint: .isDirectory))
    }

    private var currentURL: URL { folder.appending(path: "bot-game.json") }
    private var pendingURL: URL { folder.appending(path: "bot-game-pending.json") }

    /// The game in progress, or nil. A file that no longer makes a legal,
    /// unfinished game is removed.
    func current() -> BotGameSnapshot? {
        guard let snapshot: BotGameSnapshot = read(currentURL) else { return nil }
        guard let game = snapshot.restored(), !game.isOver else {
            write(nil as BotGameSnapshot?, to: currentURL)
            return nil
        }
        return snapshot
    }

    /// Pass nil when the game is over or given up.
    func setCurrent(_ snapshot: BotGameSnapshot?) {
        write(snapshot, to: currentURL)
    }

    func pending(now: Date = .now) -> PendingBotGame? {
        guard let pending: PendingBotGame = read(pendingURL) else { return nil }
        guard pending.isFresh(at: now) else {
            write(nil as PendingBotGame?, to: pendingURL)
            return nil
        }
        return pending
    }

    func setPending(_ pending: PendingBotGame?) {
        write(pending, to: pendingURL)
    }

    private func read<Value: Decodable>(_ url: URL) -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    private func write(_ value: (some Encodable)?, to url: URL) {
        do {
            guard let value else {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                return
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(value).write(to: url, options: .atomic)
        } catch {
            // A game that could not be written is played on; the next move tries again.
        }
    }
}
