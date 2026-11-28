import AuthenticationServices
import SwiftUI

/// Signing in and creating a player account: with Apple, or with an email
/// and a password. One sheet, two modes; the form is the screen's plate.
struct SignInView: View {
    enum Mode: String, Identifiable {
        case signIn, createAccount

        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State var mode: Mode
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @FocusState private var focus: Field?
    @State private var google = GoogleAuthorizer()

    private enum Field { case firstName, lastName, email, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Wordmark(size: 20)
                        .padding(.bottom, CD.Space.s12)
                    Text(mode == .signIn ? "Sign in" : "Create your account")
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    if mode == .createAccount {
                        Text("Free. What you learn follows you to every device.")
                            .cdFont(.ledeSmall)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SignInWithAppleButton(mode == .signIn ? .signIn : .signUp) { request in
                    request.requestedScopes = [.fullName, .email]
                } onCompletion: { result in
                    finishApple(result)
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .disabled(isWorking)

                if app.googleSignInServer != nil {
                    Button(action: continueWithGoogle) {
                        HStack(spacing: CD.Space.s8) {
                            GoogleMark(size: 17)
                            Text(mode == .signIn ? "Sign in with Google" : "Sign up with Google")
                        }
                    }
                    .buttonStyle(ProviderButtonStyle())
                    .disabled(isWorking)
                }

                HStack(spacing: CD.Space.s12) {
                    CDHairline(color: CD.lineStrong)
                    Text("or")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                    CDHairline(color: CD.lineStrong)
                }
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    if mode == .createAccount {
                        HStack(alignment: .top, spacing: CD.Space.s12) {
                            field("First name") {
                                TextField("", text: $firstName)
                                    .textContentType(.givenName)
                                    .submitLabel(.next)
                                    .focused($focus, equals: .firstName)
                                    .onSubmit { focus = .lastName }
                            }
                            field("Last name") {
                                TextField("", text: $lastName)
                                    .textContentType(.familyName)
                                    .submitLabel(.next)
                                    .focused($focus, equals: .lastName)
                                    .onSubmit { focus = .email }
                            }
                        }
                    }
                    field("Email") {
                        TextField("", text: $email, prompt: Text("you@example.com").foregroundStyle(CD.ink4))
                            .textContentType(mode == .signIn ? .username : .emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.next)
                            .focused($focus, equals: .email)
                            .onSubmit { focus = .password }
                    }
                    field("Password", hint: mode == .createAccount ? "At least 8 characters." : nil) {
                        SecureField("", text: $password)
                            .textContentType(mode == .signIn ? .password : .newPassword)
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
                        Text(mode == .signIn ? "Sign in" : "Create account")
                    }
                }
                .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                .disabled(isWorking || !isComplete)

                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    if mode == .createAccount {
                        Text(Self.terms)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                            .tint(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Link("Forgot your password?", destination: Self.site("forgot-password"))
                            .cdFont(.small)
                            .tint(CD.ink2)
                    }
                    CDHairline()
                    Button(mode == .signIn ? "New to ChessDesk? Create an account" : "Already have an account? Sign in") {
                        error = nil
                        withAnimation(CD.Motion.state) { mode = mode == .signIn ? .createAccount : .signIn }
                    }
                    .cdFont(.small)
                    .tint(CD.accent)
                }
            }
            .plate()
            .padding(.horizontal, CD.Space.s16)
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
    }

    private static func site(_ path: String) -> URL {
        URL(string: "https://chessdesk.app/\(path)").unsafelyUnwrapped
    }

    /// Both email consents are on at sign-up, with no box to tick: say so here.
    private static let terms: AttributedString = {
        let text = "By creating an account you accept the [Terms](https://chessdesk.app/terms) and the "
            + "[Privacy Policy](https://chessdesk.app/privacy). We email you tips and offers; "
            + "every email has an unsubscribe link."
        return (try? AttributedString(markdown: text)) ?? AttributedString(text)
    }()

    private var isComplete: Bool {
        let hasNames = !firstName.trimmed.isEmpty && !lastName.trimmed.isEmpty
        return !email.trimmed.isEmpty && !password.isEmpty && (mode == .signIn || hasNames)
    }

    private func field(_ label: String, hint: String? = nil, @ViewBuilder input: () -> some View) -> some View {
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
            if let hint {
                Text(hint)
                    .cdFont(.meta)
                    .foregroundStyle(CD.ink3)
            }
        }
    }

    private func submit() {
        guard !isWorking, isComplete else { return }
        if mode == .createAccount, password.count < 8 {
            error = "Use at least 8 characters for your password."
            return
        }
        run {
            if mode == .signIn {
                try await app.signIn(email: email.trimmed, password: password)
            } else {
                try await app.signUp(
                    firstName: firstName.trimmed, lastName: lastName.trimmed, email: email.trimmed, password: password
                )
            }
        }
    }

    private func finishApple(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case let .success(authorization):
            guard let credential = AppleCredential(authorization) else {
                error = AppleSignInError.message
                return
            }
            run { try await app.signIn(with: credential) }
        case let .failure(failure):
            // Closing the sheet is a choice, not an error.
            if case .failed = AppleSignInError(failure) { error = AppleSignInError.message }
        }
    }

    private func continueWithGoogle() {
        guard !isWorking, let server = app.googleSignInServer else { return }
        error = nil
        Task {
            do {
                let credential = try await google.authorize(server: server)
                run { try await app.signIn(with: credential) }
            } catch let failure as GoogleSignInError {
                // Closing the sheet is a choice, not an error.
                if failure != .cancelled { error = failure.message }
            } catch {
                self.error = GoogleSignInError.failed.message
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
                dismiss()
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}

/// The button of another sign-in provider, drawn to sit under Apple's white
/// one: same height, same corner, the provider's own mark and wording.
private struct ProviderButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .opacity(configuration.isPressed ? 0.8 : isEnabled ? 1 : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Google's "G", in Google's colours and on Google's 18 grid: a trademark,
/// drawn as Google publishes it and never restyled to the app's palette.
private struct GoogleMark: View {
    let size: CGFloat

    private static let parts: [(Color, String)] = [
        (Color(hex: 0x4285F4), "M17.64 9.2c0-.637-.057-1.251-.164-1.84H9v3.481h4.844c-.209 1.125-.843 2.078-1.796 2.717v2.258h2.908c1.702-1.567 2.684-3.874 2.684-6.615z"),
        (Color(hex: 0x34A853), "M9 18c2.43 0 4.467-.806 5.956-2.184l-2.908-2.258c-.806.54-1.837.86-3.048.86-2.344 0-4.328-1.584-5.036-3.711H.957v2.332A8.997 8.997 0 0 0 9 18z"),
        (Color(hex: 0xFBBC05), "M3.964 10.707A5.41 5.41 0 0 1 3.682 9c0-.593.102-1.17.282-1.707V4.961H.957A8.996 8.996 0 0 0 0 9c0 1.452.348 2.827.957 4.039l3.007-2.332z"),
        (Color(hex: 0xEA4335), "M9 3.58c1.321 0 2.508.454 3.44 1.345l2.582-2.58C13.463.891 11.426 0 9 0A8.997 8.997 0 0 0 .957 4.961L3.964 7.293C4.672 5.166 6.656 3.58 9 3.58z"),
    ]

    var body: some View {
        Canvas { context, canvasSize in
            context.scaleBy(x: canvasSize.width / 18, y: canvasSize.height / 18)
            for (color, data) in Self.parts { context.fill(Path(svg: data), with: .color(color)) }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
