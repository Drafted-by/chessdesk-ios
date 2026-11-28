import Foundation

// The account's settings: `GET` and `PATCH /api/v1/settings`, and
// `PUT /api/v1/settings/primary-rating` (`lib/api/v1/settings.ts` on the
// site). Email, password and avatar are changed on the site, not here.

/// The rating sites a primary rating comes from.
nonisolated enum RatingSource: String, Codable, Hashable, Sendable {
    case lichess = "LICHESS", chesscom = "CHESSCOM", fide = "FIDE"
}

nonisolated enum EmailConsentType: String, Codable, Hashable, Sendable {
    case marketing, newsletter
}

nonisolated enum NotificationCadence: String, Hashable, Sendable {
    case daily, weekly, off
}

nonisolated struct AccountRating: Codable, Hashable, Sendable, Identifiable {
    let source: Lenient<RatingSource>
    /// "blitz", "rapid", "standard"…
    let format: String
    let value: Double
    /// "Lichess blitz", written by the server.
    let label: String

    var id: String { "\(source.raw):\(format)" }
}

nonisolated struct AccountRatings: Codable, Hashable, Sendable {
    let primary: AccountRating?
    let available: [AccountRating]
}

nonisolated struct AccountSettings: Codable, Hashable, Sendable {
    nonisolated struct Profile: Codable, Hashable, Sendable {
        var name: String
        let email: String
        /// A coach's name comes from FIDE and cannot be changed.
        let nameLocked: Bool
    }

    nonisolated struct Board: Codable, Hashable, Sendable {
        nonisolated struct PieceSetChoice: Codable, Hashable, Sendable {
            let value: String
            let label: String
            let preview: String?
        }

        nonisolated struct TextureChoice: Codable, Hashable, Sendable {
            let value: String
            let label: String
            let thumbnail: String
        }

        nonisolated struct ColorScheme: Codable, Hashable, Sendable {
            let value: String
            let label: String
            let lightSquare: String
            let darkSquare: String
        }

        /// The site's default when the account never saved one (`saved` false).
        var theme: BoardPreferences.Theme
        /// Whether the account holds a board theme of its own.
        var saved: Bool
        var sound: BoardPreferences.Sound
        let pieceSets: [PieceSetChoice]
        let textures: [TextureChoice]
        let colorSchemes: [ColorScheme]
    }

    nonisolated struct Preferences: Codable, Hashable, Sendable {
        /// 1 to 5.
        let engineLines: Int
        /// 16, 22 or 28: a value stored outside the set is answered as the nearest one.
        let engineDepth: Int
        var newLinesPerDay: Int
        let newLinesPerDayChoices: [Int]
        /// Review new games automatically (on the site, in the browser).
        var autoReview: Bool
    }

    nonisolated struct Privacy: Codable, Hashable, Sendable {
        let showRating: Bool
    }

    nonisolated struct Notification: Codable, Hashable, Sendable {
        let key: String
        let label: String
        let description: String
        let inApp: Bool
        let email: Bool
        let push: Bool
        let cadence: Lenient<NotificationCadence>
    }

    nonisolated struct EmailConsent: Codable, Hashable, Sendable {
        let type: Lenient<EmailConsentType>
        let title: String
        let hint: String
        var on: Bool
    }

    var profile: Profile
    var board: Board
    var preferences: Preferences
    let privacy: Privacy
    let notifications: [Notification]
    var emailConsents: [EmailConsent]
    var reminder: DailyReminder
    var ratings: AccountRatings
}

/// `PATCH /api/v1/settings`: only what is set is sent, and only that changes.
nonisolated struct UpdateSettingsRequest: Codable, Hashable, Sendable {
    nonisolated struct Preferences: Codable, Hashable, Sendable {
        var newLinesPerDay: Int?
        var autoReview: Bool?
    }

    nonisolated struct EmailConsents: Codable, Hashable, Sendable {
        var marketing: Bool?
        var newsletter: Bool?
    }

    var name: String?
    var boardTheme: BoardPreferences.Theme?
    var boardSound: BoardPreferences.Sound?
    var preferences: Preferences?
    var emailConsents: EmailConsents?
}

nonisolated struct PrimaryRatingRequest: Codable, Sendable {
    let source: String
    let format: String
}
