import Foundation
import Testing
@testable import ChessDesk

// Helpers every suite shares: one name for each. The contract of the site
// is read by `Contract` (RepertoireSupport.swift), a canned server for the
// live client is `CannedServer`.

/// A captured answer of `Fixtures/api-v1`, decoded as the live client decodes it.
func fixture<Value: Decodable>(_ name: String, as type: Value.Type = Value.self) throws -> Value {
    try LiveAPI.decode(status: 200, data: FixtureAPI.data(name))
}

/// Waits for something a model does on its own (a reply of the opponent, a
/// request on its way, a save): returns as soon as `done` holds, and says
/// whether it did before the time ran out.
@discardableResult
func settled(within timeout: Duration = .seconds(5), _ done: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let limit = clock.now + timeout
    while clock.now < limit {
        if done() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(2))
    }
    return done()
}
