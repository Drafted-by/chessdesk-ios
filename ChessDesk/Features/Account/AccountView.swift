import StoreKit
import SwiftUI

/// "You": the account, the plan, the way to Progress, the settings, the
/// board, and what the app is made of. Opened from the profile button of
/// Today, on Today's stack.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(HomeNavigator.self) private var home
    @State private var signIn: SignInView.Mode?
    @State private var showsDeletion = false
    @State private var showsPremium = false
    @State private var managesSubscription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                Text("You")
                    .cdFont(.display)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                if let me = app.me {
                    SignedInCard(
                        me: me,
                        signOut: { app.signOut() },
                        delete: { showsDeletion = true },
                        premium: { showsPremium = true },
                        manage: { managesSubscription = true }
                    )
                } else {
                    GuestCard { signIn = $0 }
                }
                if app.isSignedIn {
                    ProgressEntry { home.open(.progress) }
                    AccountSettingsSection()
                }
                BoardSettingsSection()
                #if DEBUG
                    DeveloperSection()
                #endif
                AboutSection()
            }
            .pageGutter()
            .padding(.top, CD.Space.s8)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .debugScrollAnchor()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        // The page carries its own title, in the serif; the bar keeps the way back.
        .toolbar { ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) } }
        .cdPage()
        .sheet(item: $signIn) { SignInView(mode: $0) }
        .sheet(isPresented: $showsDeletion) { DeleteAccountView() }
        .sheet(isPresented: $showsPremium) { PremiumSheet() }
        .manageSubscriptionsSheet(isPresented: $managesSubscription)
        #if DEBUG
            .onAppear {
                if DebugLaunch.opensSignIn { signIn = .signIn }
                if DebugLaunch.opensSignUp { signIn = .createAccount }
                if DebugLaunch.opensDeletion { showsDeletion = true }
            }
        #endif
    }
}

/// The way to Progress: the streak, the mistakes mastered, the patterns of
/// the player's games and the rating goal.
private struct ProgressEntry: View {
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            FeatureRow(
                emblem: .insights,
                title: "Your progress",
                detail: "Your streak, the mistakes you no longer make, your rating goal."
            )
            .cardSurface()
            .hairline()
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .accessibilityElement(children: .combine)
    }
}

private struct GuestCard: View {
    let open: (SignInView.Mode) -> Void

    @Environment(AppModel.self) private var app

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Keep what you learn")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text(summary)
                    .cdFont(.lede)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Create an account") { open(.createAccount) }
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .padding(.top, CD.Space.s4)
                Button("Sign in") { open(.signIn) }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
            }
        }
    }

    private var summary: String {
        let learned = app.guestProgress.grades.values.reduce(0) { $0 + $1.count { $0.grade == .good } }
        if learned > 0 {
            return "You have learned \(CDFormat.plural(learned, "move")) on this device. Create an account and they move to it, with reviews on every device."
        }
        return "You can learn without an account: your progress stays on this device. An account keeps it on every device and brings your reviews."
    }
}

private struct SignedInCard: View {
    let me: Me
    let signOut: () -> Void
    let delete: () -> Void
    let premium: () -> Void
    let manage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
            if !me.user.emailVerified { VerifyEmailNotice(email: me.user.email) }
            CDCard(padding: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    VStack(alignment: .leading, spacing: CD.Space.s4) {
                        Text(me.user.name)
                            .cdFont(.plateTitle)
                            .foregroundStyle(CD.ink)
                        Text(me.user.email)
                            .cdFont(.small)
                            .foregroundStyle(CD.ink3)
                    }
                    CDHairline()
                    HStack(alignment: .firstTextBaseline) {
                        Text("Plan")
                            .cdFont(.body)
                            .foregroundStyle(CD.ink2)
                        Spacer()
                        if me.access.premium {
                            CDBadge(text: "Premium", tone: .premium)
                        } else {
                            Text("Free")
                                .cdFont(.bodyStrong)
                                .foregroundStyle(CD.ink)
                        }
                    }
                    if let detail = planDetail {
                        Text(detail)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .cdNumber()
                    }
                }
            }
            if !me.access.premium {
                Button("See Premium", action: premium)
                    .buttonStyle(.cd(.primary, fullWidth: true))
            } else if me.access.viaAppStore == true {
                Button("Manage subscription", action: manage)
                    .buttonStyle(.cd(.secondary, fullWidth: true))
            }
            Button("Sign out", action: signOut)
                .buttonStyle(.cd(.secondary, fullWidth: true))
            Button("Delete account", action: delete)
                .buttonStyle(.cd(.ghost, fullWidth: true))
        }
    }

    private var planDetail: String? {
        if me.access.trial.status == "active", let days = me.access.trial.daysLeft {
            return "Free trial, \(CDFormat.plural(days, "day")) left."
        }
        if me.access.viaCoachPlan { return "Included with your coach's plan." }
        if me.access.viaAppStore == true { return "Subscribed through the App Store." }
        if me.access.paid { return "Subscribed on chessdesk.app: manage it there." }
        if !me.access.premium { return "The first line of every course is free." }
        return nil
    }
}

/// Shown until the address is verified: the server gives a new player 24
/// hours, then asks for the click before anything else.
private struct VerifyEmailNotice: View {
    let email: String

    @Environment(AppModel.self) private var app
    @State private var note: String?
    @State private var failed = false
    @State private var isWorking = false

    var body: some View {
        CDCard(tone: .raised, padding: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("Verify your email")
                    .cdFont(.plateTitle)
                    .foregroundStyle(CD.ink)
                Text("We sent a link to \(email). Open it within 24 hours to keep your account open.")
                    .cdFont(.ledeSmall)
                    .foregroundStyle(CD.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: resend) {
                    if isWorking { ProgressView().tint(CD.ink) } else { Text("Send the link again") }
                }
                .buttonStyle(.cd(.secondary, fullWidth: true))
                .disabled(isWorking)
                if let note {
                    Text(note)
                        .cdFont(.small)
                        .foregroundStyle(failed ? CD.loss : CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        // The link is opened in Mail or a browser: look again on return.
        .task { await app.reloadAccount() }
    }

    private func resend() {
        isWorking = true
        Task {
            defer { isWorking = false }
            do {
                try await app.resendVerification()
                failed = false
                note = "Sent. Look in your inbox, and in spam."
            } catch let failure as APIError {
                failed = true
                note = failure.message
            } catch {
                failed = true
                note = APIError.unreadable.message
            }
        }
    }
}

private struct AboutSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s12) {
            SectionHeader(title: "About")
            CDCard {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    HStack {
                        Wordmark(size: 20)
                        Spacer()
                        Text(version)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink4)
                            .cdNumber()
                    }
                    CDHairline()
                    Text("ChessDesk for iOS is free software under the GNU General Public License, version 3. It includes the Stockfish 19 chess engine (GPL-3.0), which checks your moves on this device.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Link("Source code: github.com/Drafted-by/chessdesk-ios", destination: sourceURL)
                        .cdFont(.meta)
                        .tint(CD.ink2)
                    Text("Chess pieces by Colin M.L. Burnett, used under the BSD licence. Typefaces: Newsreader by Production Type and Geist by Vercel, SIL Open Font License 1.1.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sourceURL: URL {
        URL(string: "https://github.com/Drafted-by/chessdesk-ios").unsafelyUnwrapped
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "Version \(short) (\(build))"
    }
}

#if DEBUG
    /// Debug builds only: which backend the app talks to.
    private struct DeveloperSection: View {
        @Environment(AppModel.self) private var app

        private let choices: [Backend] = [.sampleData, .localDevelopment, .production]

        var body: some View {
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                SectionHeader(
                    title: "Developer",
                    detail: "Debug builds only. Sample data is a guest's view (the sample player with -CDFixturePlayer YES); localhost:3000 is a dev server forwarded from a Codespace."
                )
                VStack(spacing: 0) {
                    ForEach(Array(choices.enumerated()), id: \.offset) { index, backend in
                        if index > 0 { CDHairline() }
                        Button {
                            app.use(backend)
                        } label: {
                            HStack {
                                Text(backend.label)
                                    .cdFont(.body)
                                    .foregroundStyle(CD.ink)
                                Spacer()
                                if backend == app.backend {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(CD.accent)
                                }
                            }
                            .padding(.horizontal, CD.Space.s16)
                            .frame(minHeight: 48)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(CDPressStyle())
                    }
                }
                .cardSurface()
                .hairline()
            }
        }
    }
#endif
