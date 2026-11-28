import SwiftUI

/// The first launch, once: what ChessDesk does with a player's own games,
/// and the one thing asked, their username on Chess.com or Lichess. The
/// username is kept until the account exists (games belong to an account),
/// then linked and imported without being asked again. Nothing here is
/// required: "Look around first" closes it, and everything that works
/// without an account still does.
struct FirstLaunchView: View {
    /// Closes the cover and remembers that it was seen.
    let close: () -> Void

    @Environment(AppModel.self) private var app
    @State private var provider: GameProvider = .chesscom
    @State private var username = ""
    @State private var signIn: SignInView.Mode?
    @FocusState private var isTyping: Bool

    private var trimmed: String { username.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s24) {
                Wordmark(size: 20)

                VStack(alignment: .leading, spacing: CD.Space.s8) {
                    Text("Train on the games you actually play")
                        .cdFont(.display)
                        .foregroundStyle(CD.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    Text("ChessDesk reads your games, finds where they went wrong, and turns those moments into your training.")
                        .cdFont(.lede)
                        .foregroundStyle(CD.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: CD.Space.s16) {
                    step(.import, "Your games come in", "From Chess.com and Lichess, with your username. No password is asked.")
                    step(.review, "The engine reviews them", "Stockfish runs on this phone and marks the moves that cost you.")
                    step(.mistakes, "Your mistakes come back", "As positions to solve, until you find the better move.")
                }

                VStack(alignment: .leading, spacing: CD.Space.s12) {
                    Text("Where do you play?")
                        .cdFont(.plateTitle)
                        .foregroundStyle(CD.ink)
                    CDSegmented(
                        options: GameProvider.allCases.map { ($0, $0.name) },
                        selection: $provider
                    )
                    TextField("", text: $username, prompt: Text("Your \(provider.name) username").foregroundStyle(CD.ink4))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .submitLabel(.continue)
                        .focused($isTyping)
                        .onSubmit(bringIn)
                        .cdFont(.body)
                        .foregroundStyle(CD.ink)
                        .padding(.horizontal, CD.Space.s12)
                        .frame(minHeight: 48)
                        .background(CD.surface3, in: RoundedRectangle(cornerRadius: CD.Radius.md, style: .continuous))
                        .hairline(CD.lineStrong, radius: CD.Radius.md)
                        .accessibilityLabel("\(provider.name) username")
                    Button("Bring in my games", action: bringIn)
                        .buttonStyle(.cd(.primary, size: .large, fullWidth: true))
                        .disabled(trimmed.isEmpty)
                    Text("Your games are kept in a free ChessDesk account, created at the next step.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .plate()

                VStack(spacing: CD.Space.s4) {
                    Button("I already have an account") {
                        // An existing account has its own linked usernames.
                        PendingGameAccount.clear()
                        signIn = .signIn
                    }
                        .buttonStyle(.cd(.ghost, fullWidth: true))
                    Button("Look around first", action: close)
                        .buttonStyle(.cd(.ghost, fullWidth: true))
                }
            }
            .pageGutter()
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s40)
            .frame(maxWidth: CD.readingWidth)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(CD.canvas.ignoresSafeArea())
        .sheet(item: $signIn) { SignInView(mode: $0) }
        // With an account, the home takes over: it links the username given
        // here, or asks "Where do you play?" itself.
        .onChange(of: app.isSignedIn) { _, signedIn in if signedIn { close() } }
    }

    private func step(_ emblem: Emblem.Kind, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: CD.Space.s12) {
            Emblem(kind: emblem, size: 40, surface: CD.canvas)
            VStack(alignment: .leading, spacing: CD.Space.s2) {
                Text(title)
                    .cdFont(.serifCard)
                    .foregroundStyle(CD.ink)
                Text(detail)
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func bringIn() {
        guard !trimmed.isEmpty else { return }
        PendingGameAccount(provider: provider, username: trimmed).save()
        isTyping = false
        signIn = .createAccount
    }
}

extension FirstLaunchView {
    static let seenKey = "cd.firstLaunch.seen"
}

#Preview {
    FirstLaunchView(close: {}).environment(AppModel(backend: .sampleData))
}
