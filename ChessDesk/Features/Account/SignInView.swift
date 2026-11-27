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

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
