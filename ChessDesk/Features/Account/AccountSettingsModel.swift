import Foundation
import Observation

/// The account's settings, and the board appearance and sound kept in step
/// with them. Signed in, the account is the source: its board is applied to
/// every board of the app, and a change made here is written back with
/// `PATCH /api/v1/settings`. A write the server refuses (or that cannot reach
/// it) is undone on the device and said. A guest's board stays on the device.
@Observable
final class AccountSettingsModel {
    enum Phase: Equatable {
        case guest
        case loading
        case ready
        case failed(String)
    }

    /// A sentence about the last change: saved, or why it was not.
    struct Notice: Equatable {
        let text: String
        let isError: Bool
    }

    private(set) var phase: Phase = .guest
    private(set) var settings: AccountSettings?
    private(set) var notice: Notice?
    /// A write in flight; controls wait for it.
    private(set) var isSaving = false

    let preferences: BoardPreferences
    private var api: (any ChessDeskAPI)?
    private var token: String?
    /// The board as the account holds it: what a failed write goes back to,
    /// and how a change made here is told from one applied from the account.
    private var accountTheme: BoardPreferences.Theme?
    private var accountSound: BoardPreferences.Sound?
    private var boardWrite: Task<Void, Never>?
    /// How long the board waits for the slider to settle before writing.
    private let boardDelay: Duration

    init(preferences: BoardPreferences = .shared, boardDelay: Duration = .milliseconds(600)) {
        self.preferences = preferences
        self.boardDelay = boardDelay
    }

    var isSignedIn: Bool { token != nil }

    /// The account changed (sign-in, sign-out, launch): read its settings,
    /// or go back to the device's own.
    func attach(api: any ChessDeskAPI, token: String?) async {
        boardWrite?.cancel()
        self.api = api
        self.token = token
        notice = nil
        guard token != nil else {
            phase = .guest
            settings = nil
            accountTheme = nil
            accountSound = nil
            return
        }
        await reload()
    }

    func reload() async {
        guard let api, let token else { return }
        if settings == nil { phase = .loading }
        do {
            let fresh = try await api.settings(token: token)
            guard token == self.token else { return }
            let deviceTheme = preferences.theme
            let deviceSound = preferences.sound
            if !fresh.board.saved, !deviceTheme.isStandard {
                // An account that never saved a board takes the one chosen on
                // this device, as what a guest learned moves to the account.
                settings = fresh
                accountTheme = fresh.board.theme.normalized()
                accountSound = fresh.board.sound.normalized()
                phase = .ready
                await write(UpdateSettingsRequest(boardTheme: deviceTheme, boardSound: deviceSound))
            } else {
                adopt(fresh)
                phase = .ready
            }
        } catch is CancellationError {
        } catch let error as APIError {
            if settings == nil { phase = .failed(error.message) }
        } catch {
            if settings == nil { phase = .failed(APIError.unreadable.message) }
        }
    }

    /// The account's answer becomes what the app shows, the board included.
    private func adopt(_ fresh: AccountSettings) {
        settings = fresh
        let theme = fresh.board.theme.normalized()
        let sound = fresh.board.sound.normalized()
        accountTheme = theme
        accountSound = sound
        if preferences.theme != theme { preferences.theme = theme }
        if preferences.sound != sound { preferences.sound = sound }
    }

    // MARK: Board and sound

    /// Called when the board appearance or sound changes on the device. A
    /// change applied from the account is not written back.
    func boardChanged() {
        guard isSignedIn, accountTheme != nil else { return }
        let theme = preferences.theme
        let sound = preferences.sound
        guard theme != accountTheme || sound != accountSound else { return }
        boardWrite?.cancel()
        boardWrite = Task { [boardDelay] in
            try? await Task.sleep(for: boardDelay)
            guard !Task.isCancelled else { return }
            await self.writeBoard(theme: theme, sound: sound)
        }
    }

    /// Waits for the board change in flight, if any (tests).
    func settleBoard() async { await boardWrite?.value }

    private func writeBoard(theme: BoardPreferences.Theme, sound: BoardPreferences.Sound) async {
        var request = UpdateSettingsRequest()
        if theme != accountTheme { request.boardTheme = theme }
        if sound != accountSound { request.boardSound = sound }
        guard request.boardTheme != nil || request.boardSound != nil else { return }
        await write(request, savedText: nil)
    }

    // MARK: Profile, training, emails

    func setName(_ name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let settings, trimmed != settings.profile.name else { return }
        await write(UpdateSettingsRequest(name: trimmed), savedText: "Name saved.") { $0.profile.name = trimmed }
    }

    func setNewLinesPerDay(_ lines: Int) async {
        await write(UpdateSettingsRequest(preferences: .init(newLinesPerDay: lines)), savedText: "Saved.") {
            $0.preferences.newLinesPerDay = lines
        }
    }

    func setAutoReview(_ on: Bool) async {
        await write(UpdateSettingsRequest(preferences: .init(autoReview: on)), savedText: "Saved.") {
            $0.preferences.autoReview = on
        }
    }

    func setEmailConsent(_ type: EmailConsentType, on: Bool) async {
        var consents = UpdateSettingsRequest.EmailConsents()
        switch type {
        case .marketing: consents.marketing = on
        case .newsletter: consents.newsletter = on
        }
        await write(UpdateSettingsRequest(emailConsents: consents), savedText: "Saved.") { settings in
            for index in settings.emailConsents.indices where settings.emailConsents[index].type.value == type {
                settings.emailConsents[index].on = on
            }
        }
    }

    /// Sends a change, showing it at once (`optimistic`); the server's answer
    /// replaces it, a refusal puts everything back as the account holds it.
    private func write(
        _ request: UpdateSettingsRequest,
        savedText: String? = nil,
        optimistic: (inout AccountSettings) -> Void = { _ in }
    ) async {
        guard let api, let token, var shown = settings else { return }
        let before = shown
        optimistic(&shown)
        settings = shown
        isSaving = true
        defer { isSaving = false }
        do {
            let fresh = try await api.updateSettings(request, token: token)
            guard token == self.token else { return }
            adopt(fresh)
            notice = savedText.map { Notice(text: $0, isError: false) }
        } catch is CancellationError {
            settings = before
        } catch {
            guard token == self.token else { return }
            settings = before
            // The board goes back to the account's.
            if let accountTheme, preferences.theme != accountTheme { preferences.theme = accountTheme }
            if let accountSound, preferences.sound != accountSound { preferences.sound = accountSound }
            notice = Notice(text: Self.failure(error), isError: true)
        }
    }

    // MARK: Reminder and rating

    func setReminder(channel: ReminderChannel, hour: Int?) async {
        guard let api, let token, let current = settings else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let reminder = try await api.setReminder(
                ReminderRequest(channel: channel, hour: channel == .off ? nil : hour, tz: TimeZone.current.identifier),
                token: token
            )
            settings?.reminder = reminder
            notice = Notice(text: "Reminder saved.", isError: false)
        } catch {
            settings = current
            notice = Notice(text: Self.failure(error), isError: true)
        }
    }

    func setPrimaryRating(_ rating: AccountRating) async {
        guard let api, let token, settings != nil else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            let ratings = try await api.setPrimaryRating(source: rating.source.raw, format: rating.format, token: token)
            settings?.ratings = ratings
            notice = Notice(text: "Saved.", isError: false)
        } catch {
            notice = Notice(text: Self.failure(error), isError: true)
        }
    }

    private static func failure(_ error: any Error) -> String {
        let message = (error as? APIError)?.message ?? APIError.unreadable.message
        return "Not saved to your account. \(message)"
    }
}
