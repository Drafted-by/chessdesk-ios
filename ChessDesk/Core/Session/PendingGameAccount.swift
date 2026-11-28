import Foundation

/// The username a newcomer gave on first launch, before having an account:
/// kept on the device until an account exists to link it to, then linked
/// once and forgotten. Public usernames only; nothing secret is kept here.
nonisolated struct PendingGameAccount: Equatable, Sendable {
    let provider: GameProvider
    let username: String

    private static let providerKey = "cd.pendingGameAccount.provider"
    private static let usernameKey = "cd.pendingGameAccount.username"

    static func load(from defaults: UserDefaults = .standard) -> PendingGameAccount? {
        guard let raw = defaults.string(forKey: providerKey), let provider = GameProvider(rawValue: raw),
              let username = defaults.string(forKey: usernameKey), !username.isEmpty else { return nil }
        return PendingGameAccount(provider: provider, username: username)
    }

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(provider.rawValue, forKey: Self.providerKey)
        defaults.set(username, forKey: Self.usernameKey)
    }

    static func clear(in defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: usernameKey)
    }
}
