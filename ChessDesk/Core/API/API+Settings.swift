import Foundation

/// The account's settings. Email, password and avatar stay on the site.
nonisolated protocol SettingsAPI {
    func settings(token: String) async throws -> AccountSettings
    /// Changes what the request sets and answers the settings as they now are.
    func updateSettings(_ request: UpdateSettingsRequest, token: String) async throws -> AccountSettings
    /// The rating shown as the player's, among `ratings.available`.
    func setPrimaryRating(source: String, format: String, token: String) async throws -> AccountRatings
}

extension LiveAPI: SettingsAPI {
    func settings(token: String) async throws -> AccountSettings {
        try await send("GET", "settings", token: token)
    }

    func updateSettings(_ request: UpdateSettingsRequest, token: String) async throws -> AccountSettings {
        try await send("PATCH", "settings", token: token, body: request)
    }

    func setPrimaryRating(source: String, format: String, token: String) async throws -> AccountRatings {
        try await send(
            "PUT", "settings/primary-rating", token: token, body: PrimaryRatingRequest(source: source, format: format)
        )
    }
}

extension FixtureAPI: SettingsAPI {
    func settings(token: String) async throws -> AccountSettings {
        try await Task.sleep(for: delay)
        return try signedInPlayer().settings()
    }

    func updateSettings(_ request: UpdateSettingsRequest, token: String) async throws -> AccountSettings {
        try await Task.sleep(for: delay)
        return try signedInPlayer().updateSettings(request)
    }

    func setPrimaryRating(source: String, format: String, token: String) async throws -> AccountRatings {
        try await Task.sleep(for: delay)
        return try signedInPlayer().setPrimaryRating(source: source, format: format)
    }
}
