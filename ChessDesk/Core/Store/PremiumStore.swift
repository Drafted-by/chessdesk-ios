import Observation
import StoreKit

/// One subscription as the Premium sheet shows it. Everything a person reads
/// (name, price, trial) comes from the App Store, in their storefront's
/// currency: no price is written in the app.
nonisolated struct PremiumOffer: Identifiable, Hashable, Sendable {
    let id: String
    /// "Yearly" or "Monthly".
    let name: String
    /// "$49.00", as the App Store formats it.
    let price: String
    /// "a year" or "a month".
    let period: String
    /// "3 days free" when this person can still have the introductory offer.
    let trial: String?

    /// "3 days free, then $49.00 a year" or "$6.99 a month".
    var terms: String {
        if let trial { return "\(trial), then \(price) \(period)" }
        return "\(price) \(period)"
    }
}

/// Premium bought in the app: the App Store catalogue, the purchase, and the
/// hand-over to the ChessDesk server, which is what actually opens Premium.
/// The app never unlocks anything from a StoreKit answer alone.
@Observable
final class PremiumStore {
    enum Catalogue: Equatable {
        case loading
        case ready([PremiumOffer])
        /// The App Store did not return the subscriptions (offline, or not on sale yet).
        case unavailable
    }

    enum Outcome: Equatable {
        case purchased
        /// Waiting for an approval (Ask to Buy): Premium arrives when it is given.
        case pending
        case cancelled
    }

    nonisolated static let yearly = "app.chessdesk.ios.premium.yearly"
    nonisolated static let monthly = "app.chessdesk.ios.premium.monthly"
    nonisolated static let productIDs = [yearly, monthly]

    private(set) var catalogue: Catalogue = .loading

    private let app: AppModel
    private var products: [String: Product] = [:]
    private var updates: Task<Void, Never>?
    /// Transactions on their way to the server, and those it has recorded
    /// for the account signed in: each one is presented once. The listener
    /// and the reading of the entitlements both come across an unfinished
    /// transaction; without this the server was sent it twice.
    private var deliveries: [UInt64: Task<Void, any Error>] = [:]
    private var recorded: Set<UInt64> = []

    init(app: AppModel) {
        self.app = app
    }

    /// True while the store listens for transactions.
    var isListening: Bool { updates != nil }

    /// Listens for transactions that arrive outside a purchase: a renewal, an
    /// approved Ask to Buy, a purchase made on another device, and the ones
    /// left unfinished because the server could not be reached.
    ///
    /// Only for a player signed in to ChessDesk. A transaction is of no use
    /// without an account to attach it to (`deliver` drops it), and a guest
    /// must not have the App Store queried in their name at launch: the app
    /// makes no StoreKit call at all until there is an account, or until the
    /// Premium sheet is opened. Nothing is lost by waiting: StoreKit keeps an
    /// unfinished transaction and hands it over when listening starts.
    func start() {
        guard updates == nil, app.isSignedIn else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                try? await self?.deliver(result)
            }
        }
    }

    /// The player signed out: the App Store is left alone again.
    func stop() {
        updates?.cancel()
        updates = nil
        // What was recorded was recorded for that account.
        recorded = []
    }

    func load() async {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: "CDPremiumPreview") {
                catalogue = .ready(Self.previewOffers)
                return
            }
        #endif
        if case .ready = catalogue { return }
        catalogue = .loading
        guard let found = try? await Product.products(for: Self.productIDs), !found.isEmpty else {
            catalogue = .unavailable
            return
        }
        var offers: [PremiumOffer] = []
        // Yearly first: it is the one the sheet selects.
        for id in Self.productIDs {
            guard let product = found.first(where: { $0.id == id }), let offer = await Self.offer(for: product)
            else { continue }
            products[id] = product
            offers.append(offer)
        }
        catalogue = offers.isEmpty ? .unavailable : .ready(offers)
    }

    /// Buys the subscription. `purchased` means the server has recorded it
    /// and the account is Premium. Throws what the server answered when it
    /// refused, or `APIError.offline` when it could not be reached: the
    /// purchase is then kept by StoreKit and delivered at the next launch.
    func purchase(_ offer: PremiumOffer) async throws -> Outcome {
        guard let product = products[offer.id] else { throw APIError.unreadable }
        switch try await product.purchase() {
        case let .success(result):
            try await deliver(result)
            return .purchased
        case .pending:
            return .pending
        case .userCancelled:
            return .cancelled
        @unknown default:
            return .cancelled
        }
    }

    /// "Restore purchases": asks the App Store again, then presents what the
    /// Apple Account holds. True when the account ends up Premium.
    ///
    /// `AppStore.sync()` is the one StoreKit call that asks the person to
    /// sign in to their Apple Account. It belongs to this button and is
    /// never made anywhere else: not at launch, not on an account change.
    func restore() async throws -> Bool {
        try await AppStore.sync()
        try await presentEntitlements()
        return app.hasPremium
    }

    /// At launch and after every account change. Signed in: the store
    /// listens, and what this Apple Account is entitled to is presented to
    /// the server, so a purchase the server missed (or one made on another
    /// device) reaches the account. These are reads of what the device
    /// already holds; they never ask for the Apple Account. Signed out: the
    /// store stops listening and StoreKit is not called.
    func syncEntitlements() async {
        guard app.isSignedIn else {
            stop()
            return
        }
        start()
        try? await presentEntitlements()
    }

    private func presentEntitlements() async throws {
        guard app.isSignedIn else { return }
        var failure: (any Error)?
        for await result in Transaction.currentEntitlements {
            do { try await deliver(result) } catch { failure = error }
        }
        if let failure { throw failure }
    }

    /// The server verifies Apple's signature itself, so the signed form is
    /// sent whatever StoreKit thinks of it. Finished only once recorded: an
    /// unfinished transaction comes back through `Transaction.updates`.
    private func deliver(_ result: VerificationResult<Transaction>) async throws {
        guard app.isSignedIn else { return }
        let payload = result.unsafePayloadValue
        guard Self.productIDs.contains(payload.productID), !recorded.contains(payload.id) else { return }
        // Already on its way: wait for that answer instead of asking twice.
        if let running = deliveries[payload.id] { return try await running.value }
        let sending = Task { [app] in try await app.recordApplePurchase(result.jwsRepresentation) }
        deliveries[payload.id] = sending
        defer { deliveries[payload.id] = nil }
        try await sending.value
        recorded.insert(payload.id)
        if case let .verified(transaction) = result { await transaction.finish() }
    }

    // MARK: Wording

    private static func offer(for product: Product) async -> PremiumOffer? {
        guard let subscription = product.subscription else { return nil }
        var trial: String?
        if let intro = subscription.introductoryOffer, intro.paymentMode == .freeTrial,
           await subscription.isEligibleForIntroOffer {
            trial = "\(length(intro.period.value, intro.period.unit)) free"
        }
        return PremiumOffer(
            id: product.id,
            name: subscription.subscriptionPeriod.unit == .year ? "Yearly" : "Monthly",
            price: product.displayPrice,
            period: each(subscription.subscriptionPeriod.value, subscription.subscriptionPeriod.unit),
            trial: trial
        )
    }

    /// "3 days", "1 week".
    static func length(_ value: Int, _ unit: Product.SubscriptionPeriod.Unit) -> String {
        let name = switch unit {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        @unknown default: "period"
        }
        return CDFormat.plural(value, name)
    }

    /// "a year", "a month", "every 3 months".
    static func each(_ value: Int, _ unit: Product.SubscriptionPeriod.Unit) -> String {
        guard value == 1 else { return "every \(length(value, unit))" }
        return switch unit {
        case .day: "a day"
        case .week: "a week"
        case .month: "a month"
        case .year: "a year"
        @unknown default: "a period"
        }
    }

    #if DEBUG
        /// `-CDPremiumPreview YES`: the sheet with stand-in offers, for
        /// screenshots. `simctl launch` has no StoreKit configuration.
        static let previewOffers = [
            PremiumOffer(id: yearly, name: "Yearly", price: "$49.00", period: "a year", trial: "3 days free"),
            PremiumOffer(id: monthly, name: "Monthly", price: "$6.99", period: "a month", trial: "3 days free"),
        ]
    #endif
}
