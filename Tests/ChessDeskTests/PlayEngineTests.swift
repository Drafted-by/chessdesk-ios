import ChessCore
import Foundation
import Testing
@testable import ChessDesk

// The engines of the bots: the small ONNX runner, the encoding of the Maia
// network (the expectations of the site's `maia-encoding.test.ts`), and the
// choice between Maia and Stockfish (`select.test.ts`).

@Suite struct OnnxOperatorTests {
    private func floats(_ shape: [Int], _ values: [Float]) -> OnnxTensor { OnnxTensor(shape: shape, floats: values) }
    private func ints(_ shape: [Int], _ values: [Int]) -> OnnxTensor { OnnxTensor(shape: shape, ints: values) }

    private func close(_ lhs: [Float], _ rhs: [Float], tolerance: Float = 1e-5) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { abs($0 - $1) <= tolerance }
    }

    @Test func arithmeticBroadcastsLikeNumPy() throws {
        let matrix = floats([2, 3], [1, 2, 3, 4, 5, 6])
        #expect(try OnnxOps.binary(.add, matrix, floats([3], [10, 20, 30])).floats == [11, 22, 33, 14, 25, 36])
        #expect(try OnnxOps.binary(.multiply, matrix, floats([2, 1], [2, -1])).floats == [2, 4, 6, -4, -5, -6])
        #expect(try OnnxOps.binary(.subtract, floats([], [1]), matrix).floats == [0, -1, -2, -3, -4, -5])
        #expect(try OnnxOps.binary(.divide, matrix, floats([], [2])).floats == [0.5, 1, 1.5, 2, 2.5, 3])
        #expect(try OnnxOps.binary(.power, matrix, floats([], [2])).floats == [1, 4, 9, 16, 25, 36])
        #expect(try OnnxOps.binary(.add, matrix, floats([3], [10, 20, 30])).shape == [2, 3])
        #expect(throws: OnnxError.self) { try OnnxOps.binary(.add, matrix, self.floats([2], [1, 2])) }
    }

    @Test func integersKeepShapesAndIndicesExact() throws {
        #expect(try OnnxOps.binary(.multiply, ints([3], [1, 64, 96]), ints([], [2])).ints == [2, 128, 192])
        #expect(try OnnxOps.binary(.divide, ints([1], [7]), ints([1], [2])).ints == [3])
        // The remainder takes the sign of the divisor, as in ONNX.
        #expect(try OnnxOps.binary(.modulo, ints([2], [-1, 7]), ints([1], [4])).ints == [3, 3])
        #expect(try OnnxOps.binary(.equal, ints([3], [1, 0, 2]), ints([3], [1, 1, 2])).ints == [1, 0, 1])
        #expect(try OnnxOps.whereOp(ints([3], [1, 0, 1]), ints([3], [7, 8, 9]), ints([1], [0])).ints == [7, 0, 9])
        #expect(try OnnxOps.cast(ints([2], [3, -1]), to: 1).floats == [3, -1])
        #expect(try OnnxOps.cast(floats([2], [2.9, 0]), to: 7).ints == [2, 0])
    }

    @Test func matricesMultiply() throws {
        let lhs = floats([2, 3], [1, 2, 3, 4, 5, 6])
        let rhs = floats([3, 2], [7, 8, 9, 10, 11, 12])
        #expect(try OnnxOps.matmul(lhs, rhs).floats == [58, 64, 139, 154])
        // A stack against one matrix, and a stack against a stack.
        let stack = floats([2, 1, 2], [1, 2, 3, 4])
        #expect(try OnnxOps.matmul(stack, floats([2, 2], [1, 0, 0, 1])).floats == [1, 2, 3, 4])
        let pair = try OnnxOps.matmul(stack, floats([2, 2, 1], [1, 1, 2, 0]))
        #expect(pair.shape == [2, 1, 1])
        #expect(pair.floats == [3, 6])
        // Gemm with transB: y = x Wᵀ + b.
        let gemm = try OnnxOps.gemm(
            floats([1, 2], [1, 2]), floats([3, 2], [1, 0, 0, 1, 1, 1]), floats([3], [10, 20, 30]),
            alpha: 1, beta: 1, transA: false, transB: true
        )
        #expect(gemm.shape == [1, 3])
        #expect(gemm.floats == [11, 22, 33])
    }

    @Test func theTwoContractionsOfTheNetwork() throws {
        // bid,bjd->bij: every row of A against every row of B.
        let lhs = floats([1, 2, 2], [1, 2, 3, 4])
        let rhs = floats([1, 3, 2], [1, 0, 0, 1, 1, 1])
        let pairs = try OnnxOps.einsum("bid,bjd->bij", lhs, rhs)
        #expect(pairs.shape == [1, 2, 3])
        #expect(pairs.floats == [1, 2, 3, 3, 4, 7])
        // bhi,oi->bho: a linear layer without bias.
        let projected = try OnnxOps.einsum("bhi,oi->bho", lhs, floats([3, 2], [1, 0, 0, 1, 1, 1]))
        #expect(projected.shape == [1, 2, 3])
        #expect(projected.floats == [1, 2, 3, 3, 4, 7])
        #expect(throws: OnnxError.unsupported("Einsum ij->ji")) { try OnnxOps.einsum("ij->ji", lhs, rhs) }
    }

    @Test func normalisation() throws {
        let soft = try OnnxOps.softmax(floats([2, 2], [0, 0, 1, 2]), axis: -1)
        #expect(close(soft.floats, [0.5, 0.5, 0.2689414, 0.7310586]))
        let normal = try OnnxOps.layerNormalization(
            floats([1, 4], [1, 2, 3, 4]), scale: floats([4], [1, 1, 2, 2]), bias: floats([4], [0, 1, 0, 1]),
            axis: -1, epsilon: 0
        )
        #expect(close(normal.floats, [-1.3416408, 0.5527864, 0.8944272, 3.6832815]))
        let tensor = floats([2, 2, 2], [1, 2, 3, 4, 5, 6, 7, 8])
        #expect(try OnnxOps.reduceMean(tensor, axes: [1], keepDimensions: false).floats == [2, 3, 6, 7])
        let last = try OnnxOps.reduceMean(tensor, axes: [-1], keepDimensions: true)
        #expect(last.shape == [2, 2, 1])
        #expect(last.floats == [1.5, 3.5, 5.5, 7.5])
        #expect(OnnxOps.relu(floats([3], [-1, 0, 2])).floats == [0, 0, 2])
        #expect(OnnxOps.clip(floats([3], [-1, 0.5, 9]), low: 0, high: 1).floats == [0, 0.5, 1])
        #expect(close(OnnxOps.erf(floats([3], [0, 1, -1])).floats, [0, 0.8427008, -0.8427008]))
    }

    @Test func valuesMoveWhereTheShapeSays() throws {
        let tensor = floats([2, 3], [1, 2, 3, 4, 5, 6])
        #expect(try OnnxOps.transpose(tensor, permutation: [1, 0]).floats == [1, 4, 2, 5, 3, 6])
        let cube = floats([2, 2, 2], [1, 2, 3, 4, 5, 6, 7, 8])
        let turned = try OnnxOps.transpose(cube, permutation: [2, 0, 1])
        #expect(turned.shape == [2, 2, 2])
        #expect(turned.floats == [1, 3, 5, 7, 2, 4, 6, 8])
        #expect(try OnnxOps.reshape(tensor, to: [-1, 2]).shape == [3, 2])
        #expect(try OnnxOps.reshape(tensor, to: [0, -1]).shape == [2, 3])
        #expect(throws: OnnxError.self) { try OnnxOps.reshape(tensor, to: [4, -1]) }
        #expect(try OnnxOps.unsqueeze(tensor, axes: [0, -1]).shape == [1, 2, 3, 1])
        #expect(try OnnxOps.squeeze(floats([1, 3, 1], [1, 2, 3]), axes: [0]).shape == [3, 1])
        #expect(try OnnxOps.squeeze(floats([1, 3, 1], [1, 2, 3]), axes: nil).shape == [3])

        let picked = try OnnxOps.gather(tensor, indices: ints([2], [2, 0]), axis: 1)
        #expect(picked.shape == [2, 2])
        #expect(picked.floats == [3, 1, 6, 4])
        let row = try OnnxOps.gather(tensor, indices: ints([], [-1]), axis: 0)
        #expect(row.shape == [3])
        #expect(row.floats == [4, 5, 6])
        #expect(throws: OnnxError.self) { try OnnxOps.gather(tensor, indices: self.ints([], [2]), axis: 0) }

        // "To the end" is written as the largest integer.
        let tail = try OnnxOps.slice(tensor, starts: [1], ends: [Int.max], axes: [1], steps: nil)
        #expect(tail.floats == [2, 3, 5, 6])
        #expect(try OnnxOps.slice(ints([4], [1, 8, 64, 32]), starts: [-2], ends: [Int.max], axes: [0], steps: nil).ints == [64, 32])
        let joined = try OnnxOps.concat([tensor, floats([2, 1], [9, 9])], axis: -1)
        #expect(joined.shape == [2, 4])
        #expect(joined.floats == [1, 2, 3, 9, 4, 5, 6, 9])
        #expect(try OnnxOps.concat([ints([1], [-1]), ints([2], [8, 32])], axis: 0).ints == [-1, 8, 32])
        let wide = try OnnxOps.expand(floats([1, 1, 2], [1, 2]), to: [2, 3, 2])
        #expect(wide.shape == [2, 3, 2])
        #expect(wide.floats == [1, 2, 1, 2, 1, 2, 1, 2, 1, 2, 1, 2])
    }
}

@Suite struct OnnxSessionTests {
    /// A network of seventeen operators made with the ONNX tools, and what
    /// the reference runtime (onnxruntime) answers for the input below.
    static let tinyModel =
        "CAg6vwcKQgoBeAoBVwoBQhIBaCIER2VtbSoPCgVhbHBoYRUAAIA/oAEBKg4KBGJldGEVAACAP6ABASoNCgZ0cmFuc0IYAaABAgoMCgFoEgFyIg" +
        "RSZWx1CiUSA3R3byIIQ29uc3RhbnQqFAoFdmFsdWUqCBABSgQAAABAoAEEChEKAXIKA3R3bxICc3EiA1BvdwoSCgJzcQoBTRIBbSIGTWF0TXVs" +
        "ClAKAW0KBXNjYWxlCgRiaWFzEgFuIhJMYXllck5vcm1hbGl6YXRpb24qFAoEYXhpcxj///////////8BoAECKhEKB2Vwc2lsb24VrMUnN6ABAQ" +
        "oRCgFuEgVzaGFwZSIFU2hhcGUKKhIEemVybyIIQ29uc3RhbnQqGAoFdmFsdWUqDBAHSggAAAAAAAAAAKABBAooCgVzaGFwZQoEemVybxIEcm93" +
        "cyIGR2F0aGVyKgsKBGF4aXMYAKABAgotEgVheGVzMCIIQ29uc3RhbnQqGgoFdmFsdWUqDggBEAdKCAAAAAAAAAAAoAEECh8KBHJvd3MKBWF4ZX" +
        "MwEgVyb3dzMSIJVW5zcXVlZXplCi0SBW1pbnVzIghDb25zdGFudCoaCgV2YWx1ZSoOCAEQB0oI//////////+gAQQKKwoFbWludXMKBXJvd3Mx" +
        "EgZ0YXJnZXQiBkNvbmNhdCoLCgRheGlzGACgAQIKIAoBbhIBdCIJVHJhbnNwb3NlKg0KBHBlcm1AAUAAoAEHChgKAXQKBnRhcmdldBICcnMiB1" +
        "Jlc2hhcGUKJxIFdGhpcmQiCENvbnN0YW50KhQKBXZhbHVlKggQAUoEmpmZPqABBAoTCgJycwoFdGhpcmQSAXMiA011bAoLCgFzEgFlIgNFcmYK" +
        "DgoBcwoBZRIBYSIDQWRkCiUKAWESAXkiB1NvZnRtYXgqFAoEYXhpcxj///////////8BoAECEgR0aW55KjsIBAgDEAFCAVdKMBk9oTot9Zg+zF" +
        "uMvtT9Y7+cyui+jNx9vyNZdj0sjKs/fgL8vnHXHr+UzPo+5bm2PioZCAQQAUIBQkoQbePXPSczbr+Foe+8ZP8xPyo7CAQIAxABQgFNSjA5D6y/" +
        "nUzqvkRb87+TD6W/+b3rv7u7cL6wO6K/KeOKPluDID7Taj++lxIhwMfnCb8qGQgDEAFCBXNjYWxlSgwAAMA/AAAAP83MTL8qGAgDEAFCBGJpYX" +
        "NKDM3MzD3NzEy+zczMPloTCgF4Eg4KDAgBEggKAggCCgIIA2ITCgF5Eg4KDAgBEggKAggDCgIIAkIECgAQEQ=="

    @Test func readsAFileAndRunsItLikeTheReferenceRuntime() throws {
        let data = try #require(Data(base64Encoded: Self.tinyModel))
        let session = try OnnxSession(data: data)
        #expect(session.inputs == ["x"])
        #expect(session.outputs == ["y"])
        let output = try session.run(["x": OnnxTensor(shape: [2, 3], floats: [0.5, -1, 2, 1.5, 0.25, -0.75])])
        let y = try #require(output["y"])
        #expect(y.shape == [3, 2])
        let expected: [Float] = [0.885549, 0.114451, 0.318428, 0.681572, 0.478016, 0.521984]
        #expect(zip(y.floats, expected).allSatisfy { abs($0 - $1) < 1e-5 })
        #expect(throws: OnnxError.malformed("missing input x")) { try session.run([:]) }
    }

    @Test func refusesWhatItCannotRun() throws {
        // Not a model at all, and a truncated one.
        #expect(throws: OnnxError.self) { try OnnxSession(data: Data("hello".utf8)) }
        let data = try #require(Data(base64Encoded: Self.tinyModel))
        #expect(throws: OnnxError.self) { try OnnxSession(data: data.prefix(200)) }
        // An operator the runner does not know is refused when loading, not mid-game.
        var graph = try OnnxGraph(data: data)
        graph.nodes[1].op = "Tanh"
        #expect(throws: OnnxError.unsupported("Tanh")) { try OnnxSession(graph: graph) }
    }
}

/// The site's `maia-encoding.test.ts`, case for case.
@Suite struct MaiaEncodingTests {
    private let afterE4 = "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"

    private var legal: [String] { Position.start.legalMoves().map(\.uci) }

    private func policy(_ scores: [String: Float]) -> [Float] {
        var policy = [Float](repeating: 0, count: MaiaEncoding.policySize)
        for (uci, score) in scores { policy[MaiaEncoding.policyIndex(uci: uci)] = score }
        return policy
    }

    @Test func theVocabularyRoundTrips() {
        for index in 0..<MaiaEncoding.policySize {
            #expect(MaiaEncoding.policyIndex(uci: MaiaEncoding.uci(policyIndex: index)) == index)
        }
    }

    @Test func aPlainMoveIsFromTimes64PlusTo() {
        // e2 = 12, e4 = 28: the network's canonical first move.
        #expect(MaiaEncoding.policyIndex(uci: "e2e4") == 796)
    }

    @Test func aPromotionSitsAbove4096() {
        #expect(MaiaEncoding.policyIndex(uci: "a7a8q") == 4096)
        #expect(MaiaEncoding.policyIndex(uci: "h7h8n") == 4096 + 7 * 32 + 7 * 4 + 3)
        #expect(MaiaEncoding.policyIndex(uci: "a7a8k") == -1)
    }

    @Test func neverReturnsAnIllegalMoveEvenIfThePolicyPeaksOnOne() throws {
        let move = try #require(MaiaEncoding.decode(policy: policy(["e1e8": 10, legal[0]: 5]), position: .start))
        #expect(legal.contains(move.uci))
        #expect(move.uci == legal[0])
    }

    @Test func picksTheHighestScoringLegalMove() {
        #expect(MaiaEncoding.decode(policy: policy([legal[3]: 9]), position: .start)?.uci == legal[3])
    }

    @Test func aBlackMoveIsReadInTheMirroredFrame() throws {
        // Black's ...e7e5 is "e2e4" once the board is mirrored.
        let position = try #require(Position(fen: afterE4))
        #expect(MaiaEncoding.mirrored("e7e5") == "e2e4")
        #expect(MaiaEncoding.mirrored("a2a1q") == "a7a8q")
        #expect(MaiaEncoding.decode(policy: policy(["e2e4": 9]), position: position)?.uci == "e7e5")
    }

    @Test func samplingOnlyEverPicksLegalMoves() throws {
        var scores = Dictionary(uniqueKeysWithValues: legal.map { ($0, Float(1)) })
        scores["e1e8"] = 50
        let policy = policy(scores)
        var seen = Set<String>()
        for step in 0..<40 {
            let move = try #require(MaiaEncoding.decode(policy: policy, position: .start, temperature: 1, random: { Double(step) / 40 }))
            #expect(legal.contains(move.uci))
            seen.insert(move.uci)
        }
        // Equal scores: the draws spread over the whole list.
        #expect(seen.count == legal.count)
    }

    @Test func samplingCanLeaveTheTopMoveAndTemperatureZeroCannot() {
        let policy = policy([legal[0]: 3, legal[5]: 2.9])
        #expect(MaiaEncoding.decode(policy: policy, position: .start)?.uci == legal[0])
        let tail = MaiaEncoding.decode(policy: policy, position: .start, temperature: 1, random: { 0.999999 })?.uci
        #expect(tail.map(legal.contains) == true)
        #expect(tail != legal[0])
        let one = MaiaEncoding.decode(policy: self.policy([legal[2]: 5]), position: .start, temperature: 0, random: { 0.1 })
        let two = MaiaEncoding.decode(policy: self.policy([legal[2]: 5]), position: .start, temperature: 0, random: { 0.9 })
        #expect(one?.uci == legal[2])
        #expect(two?.uci == legal[2])
    }

    @Test func theNucleusKeepsTheLikelyMovesOnly() {
        // One move holds 95% of the mass: with top-p 0.9 nothing else is ever drawn.
        let policy = policy(Dictionary(uniqueKeysWithValues: legal.map { ($0, $0 == "g1f3" ? Float(6) : 0) }))
        for step in 0..<20 {
            let move = MaiaEncoding.decode(policy: policy, position: .start, temperature: 1, topP: 0.9, random: { Double(step) / 20 })
            #expect(move?.uci == "g1f3")
        }
        // Without the filter the tail is reachable.
        #expect(MaiaEncoding.decode(policy: policy, position: .start, temperature: 1, topP: 1, random: { 0.999 })?.uci != "g1f3")
    }

    @Test func castlingIsListedTwiceAsOnTheSite() throws {
        let position = try #require(Position(fen: "r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
        let texts = MaiaEncoding.candidates(in: position).map(\.uci)
        #expect(texts.contains("e1g1") && texts.contains("e1h1"))
        #expect(texts.contains("e1c1") && texts.contains("e1a1"))
        // The policy speaking of "king takes rook" still castles.
        let move = try #require(MaiaEncoding.decode(policy: policy(["e1h1": 9]), position: position))
        #expect(move.uci == "e1g1")
        #expect(position.playing(move) != nil)
    }

    @Test func aPositionWithoutMovesHasNoAnswer() throws {
        let mated = try #require(Position(fen: "rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3"))
        #expect(MaiaEncoding.decode(policy: policy([:]), position: mated) == nil)
    }

    @Test func theBoardIsEncodedFromTheSideToMove() throws {
        let white = MaiaEncoding.inputs(for: .start, selfElo: 1500, opponentElo: 1500, eloMax: 5000)
        let tokens = try #require(white[MaiaEncoding.tokensName])
        #expect(tokens.shape == [1, 64, 96])
        // Every piece, once per history slot.
        #expect(tokens.floats.reduce(0, +) == 32 * 8)
        func plane(_ tensor: OnnxTensor, square: String, slot: Int = 0) -> Int? {
            let base = (Square(square)?.index ?? 0) * 96 + slot * 12
            return (0..<12).first { tensor.floats[base + $0] == 1 }
        }
        #expect(plane(tokens, square: "e1") == 5)           // the mover's king
        #expect(plane(tokens, square: "e8") == 11)          // the other king
        #expect(plane(tokens, square: "a2", slot: 7) == 0)  // a pawn, in the last history slot too
        #expect(plane(tokens, square: "e4") == nil)

        // Black to move: the board is turned, so Black's king is "white's" on e1.
        let position = try #require(Position(fen: afterE4))
        let black = try #require(MaiaEncoding.inputs(for: position, selfElo: 1100, opponentElo: 1100, eloMax: 5000)[MaiaEncoding.tokensName])
        #expect(plane(black, square: "e1") == 5)
        #expect(plane(black, square: "e5") == 6)            // White's e4 pawn, seen from Black
        #expect(plane(black, square: "e4") == nil)
        #expect(white[MaiaEncoding.selfEloName]?.floats == [1500])
    }

    @Test func ratingsAreClamped() {
        #expect(MaiaEncoding.clampElo(1499.6, max: 5000) == 1500)
        #expect(MaiaEncoding.clampElo(-20, max: 5000) == 0)
        #expect(MaiaEncoding.clampElo(9000, max: 5000) == 5000)
        #expect(MaiaEncoding.clampElo(9000, max: 3000) == 3000)
        #expect(MaiaEncoding.clampElo(.nan, max: 5000) == 0)
    }

    /// The network the server describes today is the one the encoder is for;
    /// one it describes differently is refused, so Stockfish plays instead of
    /// a network fed the wrong way.
    @Test func theEncoderKnowsTheNetworkOfTheCatalogueAndRefusesAnother() throws {
        let info = try FixtureAPI.playCatalogue().engines.maia
        #expect(MaiaEncoding.canEncode(for: info))
        func changed(_ edit: (inout [String: Any]) -> Void) throws -> MaiaEngineInfo {
            var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(info)) as? [String: Any])
            edit(&object)
            return try JSONDecoder().decode(MaiaEngineInfo.self, from: JSONSerialization.data(withJSONObject: object))
        }
        #expect(!MaiaEncoding.canEncode(for: try changed { $0["history"] = 4 }))
        #expect(!MaiaEncoding.canEncode(for: try changed { $0["policySize"] = 1858 }))
        #expect(!MaiaEncoding.canEncode(for: try changed { $0["planeOrder"] = ["bP"] }))
        #expect(!MaiaEncoding.canEncode(for: try changed { $0["inputs"] = [["name": "tokens", "dims": [1, 64, 12], "type": "float32"]] }))
        // What is a setting, not a layout, may change freely.
        #expect(MaiaEncoding.canEncode(for: try changed { $0["eloMax"] = 4000; $0["warmupBudgetMs"] = 9000 }))
    }
}

/// The real network, when it is on this simulator (it is fetched the first
/// time a game is played; `CD_MAIA_MODEL` can also point at the file). The
/// numbers are onnxruntime's for the same file: the app's runner must agree.
@Suite struct MaiaNetworkTests {
    /// The network as the captured catalogue describes it.
    nonisolated static let model = try? FixtureAPI.playCatalogue().engines.maia

    nonisolated static var file: URL? {
        let candidates = [
            ProcessInfo.processInfo.environment["CD_MAIA_MODEL"].map { URL(fileURLWithPath: $0) },
            model.map { MaiaModelStore.shared.file(for: $0) },
        ]
        return candidates.compactMap { $0 }.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// FEN, rating, the policy's highest entry, and a few of its values.
    nonisolated static let reference: [(String, Int, Int, [(Int, Float)])] = [
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 1500, 796,
         [(0, 17.96486), (604, 20.67716), (731, 20.81505), (732, 21.47916), (795, 21.12051), (796, 21.79341)]),
        ("rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1", 408, 3707,
         [(0, 16.16155), (796, 17.56295), (830, 19.04467), (1000, 14.83384), (3705, 18.96783)]),
        ("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1", 1100, 830,
         [(0, 17.48182), (702, 19.57864), (740, 19.93544), (766, 20.02384), (796, 19.95392)]),
        ("r1bqkb1r/pppp1ppp/2n2n2/4p2Q/2B1P3/8/PPPP1PPP/RNB1K1NR w KQkq - 4 4", 723, 2549,
         [(0, 12.80333), (109, 17.77363), (429, 18.37494), (796, 13.92571), (1973, 17.67516)]),
        ("r1bq1rk1/pp2bppp/2n1pn2/2pp4/3P1B2/2PBPN2/PP1N1PPP/R2QK2R b KQ - 3 8", 1857, 1195,
         [(0, 15.43277), (147, 18.53698), (187, 18.57602), (796, 6.16726), (1189, 18.93697)]),
        ("8/P4k2/8/8/8/8/5K1p/8 w - - 0 60", 2401, 847,
         [(0, 11.81613), (271, 18.27558), (335, 18.02985), (783, 17.95015), (839, 19.7811)]),
        ("8/P4k2/8/8/8/8/5K1p/8 b - - 0 60", 945, 840,
         [(0, 16.04449), (520, 18.64226), (796, 14.30732), (840, 19.75959), (1288, 18.73536)]),
        ("6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1", 1300, 316,
         [(0, 15.66096), (316, 20.17051), (796, 14.38013), (2047, 13.67606), (4095, 16.17626)]),
    ]

    @Test(.enabled(if: MaiaNetworkTests.file != nil, "the Maia network is not on this simulator"))
    func theAppsRunnerAgreesWithTheReferenceRuntime() async throws {
        let engine = try MaiaBotEngine(model: Data(contentsOf: try #require(Self.file)), info: try #require(Self.model))
        for (fen, rating, top, values) in Self.reference {
            let position = try #require(Position(fen: fen))
            let policy = try engine.policy(for: position, rating: rating)
            #expect(policy.indices.max { policy[$0] < policy[$1] } == top, "\(fen) at \(rating)")
            for (index, value) in values {
                #expect(abs(policy[index] - value) < 2e-3, "\(fen) at \(rating): entry \(index)")
            }
            // And whatever is drawn from it is a legal move.
            let answer = try await engine.bestMove(fen: fen, strength: BotStrength(rating: rating, temperature: 1.2, stockfishElo: 1320))
            let move = try #require(Move(uci: answer))
            #expect(position.playing(move) != nil)
        }
        // The best legal move of the mate-in-one position is the mate.
        let mate = try #require(Position(fen: "6k1/5ppp/8/8/8/8/5PPP/4R1K1 w - - 0 1"))
        #expect(MaiaEncoding.decode(policy: try engine.policy(for: mate, rating: 1300), position: mate)?.uci == "e1e8")
    }
}

/// An engine that answers what it is told, when it is told.
struct StubBotEngine: BotEngine {
    var kind = BotEngineKind.stockfish
    var answer: @Sendable (String) async throws -> String

    init(kind: BotEngineKind = .stockfish, _ answer: @escaping @Sendable (String) async throws -> String) {
        self.kind = kind
        self.answer = answer
    }

    /// Always the same move.
    init(kind: BotEngineKind = .stockfish, move: String) {
        self.init(kind: kind) { _ in move }
    }

    func bestMove(fen: String, strength: BotStrength) async throws -> String {
        try await answer(fen)
    }
}

/// The site's `select.test.ts`.
@Suite struct BotEngineSelectionTests {
    private struct Failure: Error {}

    private func selection(
        maia: @escaping @Sendable () async throws -> any BotEngine,
        load: Duration = .seconds(5),
        warmup: Duration = .seconds(5),
        order: [BotEngineKind] = [.maia, .stockfish]
    ) -> BotEngineSelection {
        BotEngineSelection(
            order: order,
            makeMaia: maia,
            makeStockfish: { StubBotEngine(kind: .stockfish, move: "d2d4") },
            loadBudget: load,
            warmupBudget: warmup
        )
    }

    @Test func theCataloguesOrderAndBudgetsAreFollowed() async throws {
        let engines = try FixtureAPI.playCatalogue().engines
        let device = BotEngineSelection.device(engines)
        #expect(device.order == [.maia, .stockfish])
        #expect(device.loadBudget == .milliseconds(engines.maia.initBudgetMs))
        #expect(device.warmupBudget == .milliseconds(engines.maia.warmupBudgetMs))
        // A catalogue that puts Stockfish first gets Stockfish, Maia or not.
        let first = try await selection(maia: { StubBotEngine(kind: .maia, move: "e2e4") }, order: [.stockfish, .maia]).make()
        #expect(first.kind == .stockfish)
        // One that lists nothing this app runs has no engine to give.
        await #expect(throws: BotEngineError.self) {
            try await selection(maia: { StubBotEngine(kind: .maia, move: "e2e4") }, order: []).make()
        }
    }

    @Test func usesMaiaWhenItLoadsAndItsFirstMoveIsFast() async throws {
        let engine = try await selection(maia: { StubBotEngine(kind: .maia, move: "e2e4") }).make()
        #expect(engine.kind == .maia)
    }

    @Test func fallsBackToStockfishWhenMaiaDoesNotLoad() async throws {
        let engine = try await selection(maia: { throw Failure() }).make()
        #expect(engine.kind == .stockfish)
        #expect(try await engine.bestMove(fen: BotEngineSelection.startFEN, strength: .warmup) == "d2d4")
    }

    @Test func fallsBackToStockfishWhenTheFirstMoveIsTooSlow() async throws {
        let slow = StubBotEngine(kind: .maia) { _ in
            try await Task.sleep(for: .milliseconds(400))
            return "e2e4"
        }
        let engine = try await selection(maia: { slow }, warmup: .milliseconds(50)).make()
        #expect(engine.kind == .stockfish)
    }

    @Test func fallsBackWhenLoadingNeverEnds() async throws {
        let clock = ContinuousClock()
        let started = clock.now
        let engine = try await selection(
            maia: {
                try await Task.sleep(for: .seconds(600))
                return StubBotEngine(kind: .maia, move: "e2e4")
            },
            load: .milliseconds(100)
        ).make()
        #expect(engine.kind == .stockfish)
        #expect(clock.now - started < .seconds(5))
    }

    @Test func aGameWithoutAnyEngineSaysSo() async {
        let selection = BotEngineSelection(
            makeMaia: { throw Failure() }, makeStockfish: { throw Failure() }, loadBudget: .seconds(5), warmupBudget: .seconds(5)
        )
        await #expect(throws: Failure.self) { try await selection.make() }
    }

    @Test func aDeadlineLetsTheWorkWinWhenItIsQuick() async throws {
        #expect(try await withDeadline(.seconds(5)) { 42 } == 42)
        await #expect(throws: BotEngineError.timedOut) {
            try await withDeadline(.milliseconds(30)) {
                try await Task.sleep(for: .seconds(60))
                return 1
            }
        }
    }
}
