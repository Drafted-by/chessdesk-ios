import SwiftUI

/// You › Settings, for a signed-in player: what the site's Settings keeps on
/// the account and the app can change (`apps/web/app/settings`). Email,
/// password and avatar are changed on the site. A working screen: rows, no ornament.
struct AccountSettingsSection: View {
    @Environment(AccountSettingsModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "Settings", detail: "Saved to your account, on every device and on chessdesk.app.")
            switch model.phase {
            case .guest:
                EmptyView()
            case .loading:
                CDCard { ProgressView().tint(CD.ink3).frame(maxWidth: .infinity, minHeight: 44) }
            case let .failed(message):
                CDCard {
                    VStack(alignment: .leading, spacing: CD.Space.s8) {
                        Text("Your settings did not load.").cdFont(.bodyStrong).foregroundStyle(CD.ink)
                        Text(message).cdFont(.small).foregroundStyle(CD.ink3).fixedSize(horizontal: false, vertical: true)
                        Button("Try again") { Task { await model.reload() } }
                            .buttonStyle(.cd(.secondary, size: .small))
                    }
                }
            case .ready:
                if let settings = model.settings {
                    if let notice = model.notice { NoticeLine(notice: notice) }
                    ProfileCard(settings: settings)
                    TrainingCard(settings: settings)
                    ReminderCard(reminder: settings.reminder)
                    EmailsCard(consents: settings.emailConsents)
                    if !settings.ratings.available.isEmpty {
                        RatingCard(ratings: settings.ratings)
                    }
                }
            }
        }
    }
}

private struct NoticeLine: View {
    let notice: AccountSettingsModel.Notice

    var body: some View {
        Label(notice.text, systemImage: notice.isError ? "exclamationmark.circle" : "checkmark")
            .cdFont(.small)
            .foregroundStyle(notice.isError ? CD.loss : CD.ink2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.updatesFrequently)
    }
}

/// A titled group of rows.
private struct SettingsCard<Content: View>: View {
    let title: String
    var detail: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        CDCard {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text(title)
                        .cdFont(.cardTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    if let detail {
                        Text(detail)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
        }
    }
}

private struct ProfileCard: View {
    let settings: AccountSettings

    @Environment(AccountSettingsModel.self) private var model
    @State private var name = ""

    var body: some View {
        SettingsCard(title: "Profile", detail: "Your email, password and photo are changed on chessdesk.app.") {
            VStack(alignment: .leading, spacing: CD.Space.s6) {
                Text("Display name")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink2)
                HStack(spacing: CD.Space.s8) {
                    TextField("", text: $name)
                        .textContentType(.name)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .disabled(settings.profile.nameLocked)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink)
                        .padding(.horizontal, CD.Space.s12)
                        .frame(minHeight: 44)
                        .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                        .hairline(CD.lineStrong, radius: CD.Radius.md)
                        .accessibilityLabel("Display name")
                    if !settings.profile.nameLocked {
                        Button("Save", action: save)
                            .buttonStyle(.cd(.secondary))
                            .disabled(model.isSaving || trimmed.isEmpty || trimmed == settings.profile.name)
                    }
                }
                if settings.profile.nameLocked {
                    Text("A coach's name comes from FIDE and cannot be changed here.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                }
            }
            HStack {
                Text("Email").cdFont(.body).foregroundStyle(CD.ink2)
                Spacer()
                Text(settings.profile.email).cdFont(.body).foregroundStyle(CD.ink).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
        .onAppear { name = settings.profile.name }
        .onChange(of: settings.profile.name) { _, new in name = new }
    }

    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmed.isEmpty else { return }
        Task { await model.setName(trimmed) }
    }
}

private struct TrainingCard: View {
    let settings: AccountSettings

    @Environment(AccountSettingsModel.self) private var model

    var body: some View {
        SettingsCard(title: "Training") {
            HStack {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text("New lines per day").cdFont(.body).foregroundStyle(CD.ink)
                    Text("How many new opening lines a course teaches each day.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Menu {
                    ForEach(choices, id: \.self) { lines in
                        Button {
                            Task { await model.setNewLinesPerDay(lines) }
                        } label: {
                            if lines == settings.preferences.newLinesPerDay {
                                Label("\(lines)", systemImage: "checkmark")
                            } else {
                                Text("\(lines)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: CD.Space.s4) {
                        Text("\(settings.preferences.newLinesPerDay)").cdNumber()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                    }
                    .cdFont(.bodyStrong)
                    .foregroundStyle(CD.ink)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                }
                .disabled(model.isSaving)
                .accessibilityLabel("New lines per day, \(settings.preferences.newLinesPerDay)")
            }
            CDHairline()
            Toggle(isOn: Binding(
                get: { settings.preferences.autoReview },
                set: { on in Task { await model.setAutoReview(on) } }
            )) {
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text("Review new games automatically").cdFont(.body).foregroundStyle(CD.ink)
                    Text("On chessdesk.app, your newest games are reviewed by Stockfish when you open Home.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(CD.accent)
            .frame(minHeight: 44)
            .disabled(model.isSaving)
        }
    }

    /// The server's choices, with the current value even if it is not among them.
    private var choices: [Int] {
        let offered = settings.preferences.newLinesPerDayChoices
        let current = settings.preferences.newLinesPerDay
        return offered.contains(current) ? offered : (offered + [current]).sorted()
    }
}

/// The Daily 5 reminder: by email at an hour, or off. A browser notification
/// set on the site shows as such; the app cannot set one up.
private struct ReminderCard: View {
    let reminder: DailyReminder

    @Environment(AccountSettingsModel.self) private var model

    var body: some View {
        SettingsCard(title: "Daily 5 reminder", detail: "One short message a day, with a link straight to your first position.") {
            HStack {
                Text("Remind me").cdFont(.body).foregroundStyle(CD.ink)
                Spacer()
                Menu {
                    Button { set(.off, hour: nil) } label: { choice("Off", selected: channel == .off) }
                    Button { set(.email, hour: reminder.hour ?? Self.defaultHour) } label: {
                        choice("By email", selected: channel == .email)
                    }
                } label: {
                    menuLabel(channelLabel)
                }
                .disabled(model.isSaving)
                .accessibilityLabel("Remind me, \(channelLabel)")
            }
            if channel != .off {
                CDHairline()
                HStack {
                    Text("At").cdFont(.body).foregroundStyle(CD.ink)
                    Spacer()
                    Menu {
                        ForEach(0..<24, id: \.self) { hour in
                            Button { set(channel == .push ? .push : .email, hour: hour) } label: {
                                choice(ReminderHour.label(hour), selected: hour == reminder.hour)
                            }
                        }
                    } label: {
                        menuLabel(reminder.hour.map(ReminderHour.label) ?? "Choose")
                    }
                    .disabled(model.isSaving)
                    .accessibilityLabel("Hour, \(reminder.hour.map(ReminderHour.label) ?? "not set")")
                }
                if let zone = reminder.timezone {
                    Text("Your time, \(zone.replacingOccurrences(of: "_", with: " ")).")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                }
            }
        }
    }

    /// The hour the site offers first: the evening.
    private static let defaultHour = 18

    private var channel: ReminderChannel? { reminder.channel.value }

    private var channelLabel: String {
        switch channel {
        case .off: "Off"
        case .email: "By email"
        case .push: "Browser notification"
        case nil: reminder.channel.raw
        }
    }

    private func set(_ channel: ReminderChannel, hour: Int?) {
        Task { await model.setReminder(channel: channel, hour: hour) }
    }

    @ViewBuilder private func choice(_ text: String, selected: Bool) -> some View {
        if selected { Label(text, systemImage: "checkmark") } else { Text(text) }
    }

    private func menuLabel(_ text: String) -> some View {
        HStack(spacing: CD.Space.s4) {
            Text(text).cdNumber()
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
        }
        .cdFont(.bodyStrong)
        .foregroundStyle(CD.ink)
        .frame(minHeight: 44)
    }
}

private struct EmailsCard: View {
    let consents: [AccountSettings.EmailConsent]

    @Environment(AccountSettingsModel.self) private var model

    var body: some View {
        SettingsCard(
            title: "Emails from ChessDesk",
            detail: "Turn either off here, or with the unsubscribe link in any of these emails."
        ) {
            ForEach(Array(known.enumerated()), id: \.offset) { index, entry in
                if index > 0 { CDHairline() }
                Toggle(isOn: Binding(
                    get: { entry.consent.on },
                    set: { on in Task { await model.setEmailConsent(entry.type, on: on) } }
                )) {
                    VStack(alignment: .leading, spacing: CD.Space.s2) {
                        Text(entry.consent.title).cdFont(.body).foregroundStyle(CD.ink)
                        Text(entry.consent.hint)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(CD.accent)
                .frame(minHeight: 44)
                .disabled(model.isSaving)
            }
        }
    }

    /// Consents of a kind this version can change.
    private var known: [(consent: AccountSettings.EmailConsent, type: EmailConsentType)] {
        consents.compactMap { consent in consent.type.value.map { (consent, $0) } }
    }
}

/// The rating shown as the player's, among those the account has.
private struct RatingCard: View {
    let ratings: AccountRatings

    @Environment(AccountSettingsModel.self) private var model

    var body: some View {
        SettingsCard(title: "Your rating", detail: "The one shown as yours across ChessDesk.") {
            VStack(spacing: 0) {
                ForEach(Array(ratings.available.enumerated()), id: \.element.id) { index, rating in
                    if index > 0 { CDHairline() }
                    Button {
                        Task { await model.setPrimaryRating(rating) }
                    } label: {
                        HStack {
                            Text(rating.label).cdFont(.body).foregroundStyle(CD.ink)
                            Spacer()
                            Text(CDFormat.count(Int(rating.value.rounded())))
                                .cdFont(.bodyStrong)
                                .foregroundStyle(CD.ink2)
                                .cdNumber()
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(CD.accent)
                                .opacity(rating.id == ratings.primary?.id ? 1 : 0)
                                .frame(width: 20)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(CDPressStyle())
                    .disabled(model.isSaving)
                    .accessibilityAddTraits(rating.id == ratings.primary?.id ? .isSelected : [])
                }
            }
        }
    }
}
