import StoreKit
import SwiftUI

/// What Premium is, and where it is bought: an App Store subscription,
/// recorded by the ChessDesk server on the player's account. A commercial
/// surface: the premium plate, the seal, the price as a ledger.
struct PremiumSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(PremiumStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = PremiumStore.yearly
    @State private var note: Note?
    @State private var isWorking = false
    @State private var showsSignUp = false

    private struct Note: Equatable {
        let text: String
        var isError = false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CD.Space.s20) {
                VStack(alignment: .leading, spacing: CD.Space.s20) {
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        HStack(alignment: .center, spacing: CD.Space.s12) {
                            Emblem(kind: .premium, size: 48)
                            CDBadge(text: "Premium", tone: .premium)
                        }
                        Text(app.hasPremium ? "You have Premium" : "Every line of every course")
                            .cdFont(.pageTitle)
                            .foregroundStyle(CD.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text("The first line of each course is free. Premium opens the rest, with reviews timed so the lines stay in memory.")
                            .cdFont(.lede)
                            .foregroundStyle(CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    OrnamentRule()
                    VStack(alignment: .leading, spacing: CD.Space.s12) {
                        included("Every line of every opening course")
                        included("Reviews timed so the lines stay in memory")
                        included("One account: the same Premium as on chessdesk.app")
                    }
                    if !app.hasPremium { offers }
                    if let note {
                        Label(note.text, systemImage: note.isError ? "exclamationmark.circle" : "checkmark.circle")
                            .cdFont(.small)
                            .foregroundStyle(note.isError ? CD.loss : CD.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .plate(.premium)

                if !app.hasPremium {
                    Text("Payment is charged to your Apple Account. The subscription renews automatically until you cancel it, at least 24 hours before the end of the period, in your App Store account settings.")
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: CD.Space.s16) {
                        Button("Restore purchases", action: restore)
                            .disabled(isWorking)
                        Link("Terms", destination: Self.site("terms"))
                        Link("Privacy", destination: Self.site("privacy"))
                    }
                    .cdFont(.small)
                    .tint(CD.ink2)
                }

                Button("Close") { dismiss() }
                    .buttonStyle(.cd(.secondary, size: .large, fullWidth: true))
            }
            .padding(.horizontal, CD.Space.s16)
            .padding(.top, CD.Space.s32)
            .padding(.bottom, CD.Space.s24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(CD.canvas.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isWorking)
        .task { await store.load() }
        .sheet(isPresented: $showsSignUp) { SignInView(mode: .createAccount) }
    }

    private static func site(_ path: String) -> URL {
        URL(string: "https://chessdesk.app/\(path)").unsafelyUnwrapped
    }

    // MARK: Offers

    @ViewBuilder private var offers: some View {
        switch store.catalogue {
        case .loading:
            HStack(spacing: CD.Space.s12) {
                ProgressView().tint(CD.ink3)
                Text("Asking the App Store for the prices")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
            }
            .frame(minHeight: 48)
        case .unavailable:
            VStack(alignment: .leading, spacing: CD.Space.s12) {
                Text("The App Store did not return the subscriptions. Check your connection and try again.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Try again") { Task { await store.load() } }
                    .buttonStyle(.cd(.secondary, fullWidth: true))
            }
        case let .ready(list):
            // The price is a ledger: label left, tabular amount right.
            VStack(spacing: 0) {
                CDHairline(color: CD.lineStrong)
                ForEach(Array(list.enumerated()), id: \.element.id) { index, offer in
                    if index > 0 { CDHairline() }
                    row(offer)
                }
                CDHairline(color: CD.lineStrong)
            }
            if let offer = list.first(where: { $0.id == selected }) ?? list.first {
                Button { buy(offer) } label: {
                    if isWorking {
                        ProgressView().tint(CD.accentInk)
                    } else {
                        Text(callToAction(offer))
                    }
                }
                .buttonStyle(.cd(.lead, size: .large, fullWidth: true))
                .disabled(isWorking)
                Text(app.isSignedIn ? offer.terms.capitalizedFirst + ". Cancel at any time." : "Premium belongs to your ChessDesk account, so it follows you to every device.")
                    .cdFont(.small)
                    .foregroundStyle(CD.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func callToAction(_ offer: PremiumOffer) -> String {
        if !app.isSignedIn { return "Create an account to subscribe" }
        return offer.trial == nil ? "Subscribe" : "Start the free trial"
    }

    private func row(_ offer: PremiumOffer) -> some View {
        let isSelected = offer.id == selected
        return Button {
            selected = offer.id
        } label: {
            HStack(alignment: .center, spacing: CD.Space.s12) {
                ZStack {
                    Circle().strokeBorder(isSelected ? CD.accent : CD.lineHover, lineWidth: 1.5)
                    if isSelected { Circle().fill(CD.accent).padding(5) }
                }
                .frame(width: 20, height: 20)
                VStack(alignment: .leading, spacing: CD.Space.s2) {
                    Text(offer.name)
                        .cdFont(.bodyStrong)
                        .foregroundStyle(CD.ink)
                    if let trial = offer.trial {
                        Text(trial.capitalizedFirst)
                            .cdFont(.meta)
                            .foregroundStyle(CD.ink3)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(offer.price)
                        .font(.custom("Newsreader72pt-Medium", size: 24, relativeTo: .title2))
                        .foregroundStyle(CD.accentStrong)
                        .cdNumber()
                    Text(offer.period)
                        .cdFont(.meta)
                        .foregroundStyle(CD.ink3)
                }
            }
            .frame(minHeight: 60)
            .contentShape(Rectangle())
        }
        .buttonStyle(CDPressStyle())
        .disabled(isWorking)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(offer.name), \(offer.terms)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func included(_ text: String) -> some View {
        HStack(alignment: .center, spacing: CD.Space.s12) {
            IncludedMark()
            Text(text)
                .cdFont(.body)
                .foregroundStyle(CD.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Included: \(text)")
    }

    // MARK: Actions

    private func buy(_ offer: PremiumOffer) {
        guard app.isSignedIn else {
            showsSignUp = true
            return
        }
        run {
            switch try await store.purchase(offer) {
            case .purchased: note = Note(text: "Premium is open on your account.")
            case .pending: note = Note(text: "Waiting for approval. Premium opens as soon as it is given.")
            case .cancelled: break
            }
        }
    }

    private func restore() {
        guard app.isSignedIn else {
            note = Note(text: "Sign in first: a purchase is restored to your ChessDesk account.", isError: true)
            return
        }
        run {
            let restored = try await store.restore()
            note = restored
                ? Note(text: "Premium is open on your account.")
                : Note(text: "This Apple Account has no ChessDesk subscription to restore.", isError: true)
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        guard !isWorking else { return }
        isWorking = true
        note = nil
        Task {
            defer { isWorking = false }
            do {
                try await work()
            } catch let failure as APIError {
                note = Note(text: failure == .offline ? Self.keptForLater : failure.message, isError: true)
            } catch StoreKitError.userCancelled {
                // Closing Apple's sheet is a choice.
            } catch {
                note = Note(text: "The App Store could not complete this. Try again in a moment.", isError: true)
            }
        }
    }

    private static let keptForLater =
        "ChessDesk could not be reached. If you were charged, nothing is lost: the purchase is attached to your account the next time the app opens online."
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
