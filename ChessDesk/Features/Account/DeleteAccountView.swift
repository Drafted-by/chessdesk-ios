import SwiftUI

/// Deleting the account from the app. A working sheet, not a brand moment:
/// no plate, no ornament. An account with a password proves it; one opened
/// with Apple on this device confirms with Apple, so Apple is told too.
struct DeleteAccountView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var error: String?
    @State private var isWorking = false
    @State private var authorizer = AppleAuthorizer()

    /// Unknown (an older server) is treated as "has one": the server decides.
    private var needsPassword: Bool { app.me?.hasPassword != false }
    private var confirmsWithApple: Bool { !needsPassword && app.usedAppleSignIn }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Delete your account")
                        .cdFont(.pageTitle)
                        .foregroundStyle(CD.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Your account, your course progress, your games and your reviews are removed from ChessDesk, on every device. This cannot be undone.")
                        .cdFont(.ledeSmall)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("A subscription is not ended by deleting the account: cancel it first.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if needsPassword {
                    VStack(alignment: .leading, spacing: CD.Space.s6) {
                        Text("Your password")
                            .cdFont(.small)
                            .foregroundStyle(CD.ink2)
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .cdFont(.body)
                            .foregroundStyle(CD.ink)
                            .padding(.horizontal, CD.Space.s12)
                            .frame(minHeight: 48)
                            .background(CD.surface2, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                            .hairline(CD.lineStrong, radius: CD.Radius.md)
                    }
                } else if confirmsWithApple {
                    Text("Apple will ask you to confirm it is you.")
                        .cdFont(.small)
                        .foregroundStyle(CD.ink3)
                }

                if let error {
                    Label(error, systemImage: "exclamationmark.circle")
                        .cdFont(.small)
                        .foregroundStyle(CD.loss)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: CD.Space.s12) {
                    Button(action: delete) {
                        if isWorking { ProgressView().tint(CD.loss) } else { Text("Delete my account") }
                    }
                    .buttonStyle(.cd(.danger, size: .large, fullWidth: true))
                    .disabled(isWorking || (needsPassword && password.isEmpty))
                    Button("Keep my account") { dismiss() }
                        .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
                        .disabled(isWorking)
                }
            }
            .padding(.horizontal, CD.Space.s24)
            .padding(.top, CD.Space.s40)
            .padding(.bottom, CD.Space.s32)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .background(CD.canvas.ignoresSafeArea())
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
    }

    private func delete() {
        guard !isWorking else { return }
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do {
                var code: String?
                if confirmsWithApple { code = try await authorizer.authorize().authorizationCode }
                try await app.deleteAccount(
                    currentPassword: needsPassword ? password : nil, appleAuthorizationCode: code
                )
                dismiss()
            } catch AppleSignInError.cancelled {
                // The person closed Apple's sheet: nothing was deleted.
            } catch is AppleSignInError {
                error = AppleSignInError.message
            } catch let failure as APIError {
                error = failure.message
            } catch {
                self.error = APIError.unreadable.message
            }
        }
    }
}
