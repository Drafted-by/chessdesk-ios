import SwiftUI

/// "You": the account, the plan, and what the app is made of.
struct AccountView: View {
    @Environment(AppModel.self) private var app
    @State private var showsSignIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s32) {
                Text("You")
                    .cdFont(.display)
                    .foregroundStyle(CD.ink)
                    .accessibilityAddTraits(.isHeader)
                if let me = app.me {
                    SignedInCard(me: me) { app.signOut() }
                } else {
                    GuestCard { showsSignIn = true }
                }
                #if DEBUG
                    DeveloperSection()
                #endif
                AboutSection()
            }
            .pageGutter()
            .padding(.top, CD.Space.s24)
            .padding(.bottom, CD.Space.s56)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("You")
        .toolbar(.hidden, for: .navigationBar)
        .cdPage()
        .sheet(isPresented: $showsSignIn) { SignInView() }
        #if DEBUG
            .onAppear { if DebugLaunch.opensSignIn { showsSignIn = true } }
        #endif
    }
}

private struct GuestCard: View {
    let signIn: () -> Void

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
                Button("Sign in", action: signIn)
                    .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                    .padding(.top, CD.Space.s4)
                Text("Use your ChessDesk email and password. Accounts are created on chessdesk.app for now.")
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var summary: String {
        let learned = app.guestProgress.grades.values.reduce(0) { $0 + $1.count { $0.grade == .good } }
        if learned > 0 {
            return "You have learned \(CDFormat.plural(learned, "move")) on this device. Sign in and they move to your account, with reviews on every device."
        }
        return "You can learn without an account: your progress stays on this device. Sign in to keep it on every device and get your reviews."
    }
}

private struct SignedInCard: View {
    let me: Me
    let signOut: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s16) {
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
            Button("Sign out", action: signOut)
                .buttonStyle(.cd(.secondary, fullWidth: true))
        }
    }

    private var planDetail: String? {
        if me.access.trial.status == "active", let days = me.access.trial.daysLeft {
            return "Free trial, \(CDFormat.plural(days, "day")) left."
        }
        if me.access.viaCoachPlan { return "Included with your coach's plan." }
        if !me.access.premium { return "The first line of every course is free." }
        return nil
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
                    detail: "Debug builds only. Sample data is a guest's view of three courses; localhost:3000 is a dev server forwarded from a Codespace."
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
                .background(CD.surface1, in: RoundedRectangle(cornerRadius: CD.Radius.lg, style: .continuous))
                .hairline()
            }
        }
    }
#endif

/// Email and password sign-in. Sign in with Apple and Google come with the
/// account-creation milestone.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focus: Field?

    private enum Field { case email, password }

    var body: some View {
        VStack(alignment: .leading, spacing: CD.Space.s20) {
            VStack(alignment: .leading, spacing: CD.Space.s8) {
                Wordmark(size: 20)
                    .padding(.bottom, CD.Space.s12)
                Text("Sign in")
                    .cdFont(.pageTitle)
                    .foregroundStyle(CD.ink)
            }

            VStack(alignment: .leading, spacing: CD.Space.s16) {
                field("Email") {
                    TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(CD.ink4))
                        .textContentType(.username)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.next)
                        .focused($focus, equals: .email)
                        .onSubmit { focus = .password }
                }
                field("Password") {
                    SecureField("", text: $password)
                        .textContentType(.password)
                        .submitLabel(.go)
                        .focused($focus, equals: .password)
                        .onSubmit(submit)
                }
            }

            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .cdFont(.small)
                    .foregroundStyle(CD.loss)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: submit) {
                if isWorking {
                    ProgressView().tint(CD.accentInk)
                } else {
                    Text("Sign in")
                }
            }
            .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
            .disabled(isWorking || email.isEmpty || password.isEmpty)

        }
        .plate()
        .padding(.horizontal, CD.Space.s16)
        .padding(.top, CD.Space.s32)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .onAppear { focus = .email }
    }

    private func field(_ label: String, @ViewBuilder input: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: CD.Space.s6) {
            Text(label)
                .cdFont(.small)
                .foregroundStyle(CD.ink2)
            input()
                .cdFont(.body)
                .foregroundStyle(CD.ink)
                .padding(.horizontal, CD.Space.s12)
                .frame(minHeight: 48)
                .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                .hairline(CD.lineStrong, radius: CD.Radius.md)
        }
    }

    private func submit() {
        guard !isWorking, !email.isEmpty, !password.isEmpty else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await app.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}
