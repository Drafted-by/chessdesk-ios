import Foundation
import StoreKit
import StoreKitTest
import Testing
@testable import ChessDesk

/// The server side of a purchase, in memory: it records what the app
/// presented and answers with a Premium account, or refuses.
private final class PurchaseServer: ChessDeskAPI, @unchecked Sendable {
    private let lock = NSLock()
    private var presented: [String] = []
    private var premium = false
    var refuses = false
    private let guest = FixtureAPI(delay: .zero)

    var received: [String] { lock.withLock { presented } }

    private func account() -> Me {
        let isPremium = lock.withLock { premium }
        return Me(
            user: APIUser(id: "u1", email: "ana@example.com", name: "Ana", role: "STUDENT", emailVerified: true),
            hasPassword: true,
            access: .init(
                premium: isPremium, paid: isPremium, viaCoachPlan: false, viaAppStore: isPremium,
                trial: .init(status: "ineligible", endsAt: nil, daysLeft: nil)
            ),
            freeLimits: .init(repertoireLines: 20, explorerGames: 100)
        )
    }

    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me {
        if refuses {
            throw APIError.server(status: 422, code: "request_failed", message: "We could not confirm this purchase.")
        }
        lock.withLock {
            presented.append(signedTransaction)
            premium = true
        }
        return account()
    }

    func login(email: String, password: String) async throws -> AuthSession {
        AuthSession(token: "token", expiresAt: Date(timeIntervalSinceNow: 3600), user: account().user)
    }

    func me(token: String) async throws -> Me { account() }
    func refresh(token: String) async throws -> AuthSession { try await login(email: "", password: "") }
    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession {
        try await login(email: email, password: password)
    }

    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession {
        try await login(email: "", password: "")
    }

    func resendVerification(token: String) async throws {}
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {}
    func courses(token: String?) async throws -> [CourseCard] { try await guest.courses(token: token) }
    func course(slug: String, token: String?) async throws -> CourseDetail { try await guest.course(slug: slug, token: token) }
    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        try await guest.courseSession(slug: slug, mode: mode, line: line, token: token)
    }

    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws {}
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { grades.count }
    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {}
    func due(token: String) async throws -> DueSummary { try await guest.due(token: token) }
    func paths(token: String?) async throws -> [PathCard] { try await guest.paths(token: token) }
    func path(slug: String, token: String?) async throws -> PathDetail { try await guest.path(slug: slug, token: token) }
    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        try await guest.pathSession(slug: slug, stage: stage, token: token)
    }

    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int { grades.count }
}

/// Runs against the local StoreKit configuration (`StoreKit/Premium.storekit`):
/// the App Store of these tests is on the simulator, the server is the stub.
///
/// StoreKit testing needs a signed app. The GitHub runner builds unsigned
/// (`CODE_SIGNING_ALLOWED=NO`) and its test store answers `notEntitled`, so
/// the workflow sets `CD_SKIP_STOREKIT_TESTS`; everywhere else they run.
@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["CD_SKIP_STOREKIT_TESTS"] == nil))
struct PremiumStoreTests {
    private func session() throws -> SKTestSession {
        let url = try #require(Bundle(for: StoreBundleToken.self).url(forResource: "Premium", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    private func signedIn(_ server: PurchaseServer) async throws -> AppModel {
        let tokens = MemoryTokenStore()
        let file = FileManager.default.temporaryDirectory.appending(path: "cd-store-\(UUID().uuidString).json")
        let app = AppModel(
            backend: .sampleData, api: server, guestStore: GuestProgressStore(url: file), makeTokenStore: { _ in tokens }
        )
        try await app.signIn(email: "ana@example.com", password: "pw")
        return app
    }

    private func offers(_ store: PremiumStore) throws -> [PremiumOffer] {
        guard case let .ready(offers) = store.catalogue else {
            Issue.record("The catalogue did not load: \(store.catalogue)")
            return []
        }
        return offers
    }

    @Test func theCatalogueReadsPricesAndTrialFromTheStore() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = PremiumStore(app: try await signedIn(PurchaseServer()))
        await store.load()
        let list = try offers(store)
        #expect(list.map(\.id) == [PremiumStore.yearly, PremiumStore.monthly])
        try #require(list.count == 2)
        #expect(list.map(\.name) == ["Yearly", "Monthly"])
        #expect(list[0].terms == "3 days free, then $49.00 a year")
        #expect(list[1].terms == "3 days free, then $6.99 a month")
    }

    @Test func aPurchaseOpensPremiumOnlyOnceTheServerRecordedIt() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let server = PurchaseServer()
        let app = try await signedIn(server)
        let store = PremiumStore(app: app)
        await store.load()
        let yearly = try #require(try offers(store).first)
        #expect(!app.hasPremium)
        let outcome = try await store.purchase(yearly)
        #expect(outcome == .purchased)
        #expect(app.hasPremium)
        #expect(app.me?.access.viaAppStore == true)
        // What reached the server is the transaction Apple signed: three JWS segments.
        let jws = try #require(server.received.first)
        #expect(jws.split(separator: ".").count == 3)
    }

    @Test func aPurchaseTheServerRefusesDoesNotOpenPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let server = PurchaseServer()
        server.refuses = true
        let app = try await signedIn(server)
        let store = PremiumStore(app: app)
        await store.load()
        let monthly = try #require(try offers(store).last)
        await #expect(throws: APIError.self) { _ = try await store.purchase(monthly) }
        #expect(!app.hasPremium)
        // Kept by StoreKit: presenting the entitlements again delivers it.
        server.refuses = false
        await store.syncEntitlements()
        #expect(app.hasPremium)
    }

    @Test func aSubscriptionBoughtBeforeSigningInReachesTheAccountAtSync() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        try await session.buyProduct(identifier: PremiumStore.monthly)
        let server = PurchaseServer()
        let app = try await signedIn(server)
        let store = PremiumStore(app: app)
        #expect(server.received.isEmpty)
        await store.syncEntitlements()
        #expect(server.received.count == 1)
        #expect(app.hasPremium)
    }

}

/// A guest costs the App Store nothing: these never reach StoreKit, so they
/// run everywhere, CI included.
@Suite struct PremiumStoreGuestTests {
    private func guest() -> AppModel {
        let tokens = MemoryTokenStore()
        let file = FileManager.default.temporaryDirectory.appending(path: "cd-store-\(UUID().uuidString).json")
        return AppModel(
            backend: .sampleData, api: FixtureAPI(delay: .zero), guestStore: GuestProgressStore(url: file),
            makeTokenStore: { _ in tokens }
        )
    }

    /// At launch as a guest, the store neither listens for transactions nor
    /// reads entitlements: nothing can ask for the Apple Account.
    @Test func aGuestsLaunchMakesNoStoreKitCall() async {
        let store = PremiumStore(app: guest())
        store.start()
        #expect(!store.isListening)
        await store.syncEntitlements()
        #expect(!store.isListening)
        // The catalogue of offers is only asked when the Premium sheet opens.
        #expect(store.catalogue == .loading)
    }
}

@Suite struct PremiumWordingTests {
    @Test func periodsReadAsAPersonSaysThem() {
        #expect(PremiumStore.each(1, .year) == "a year")
        #expect(PremiumStore.each(1, .month) == "a month")
        #expect(PremiumStore.each(3, .month) == "every 3 months")
        #expect(PremiumStore.length(3, .day) == "3 days")
        #expect(PremiumStore.length(1, .week) == "1 week")
    }

    @Test func termsNameTheTrialThenThePrice() {
        let yearly = PremiumOffer(id: "y", name: "Yearly", price: "$49.00", period: "a year", trial: "3 days free")
        #expect(yearly.terms == "3 days free, then $49.00 a year")
        let monthly = PremiumOffer(id: "m", name: "Monthly", price: "$6.99", period: "a month", trial: nil)
        #expect(monthly.terms == "$6.99 a month")
    }
}

private final class StoreBundleToken {}
