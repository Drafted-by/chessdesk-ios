import Foundation
import Testing
@testable import ChessDesk

/// A canned server for the live client: it answers what it was told to and
/// remembers what it was asked. Each one has a host of its own, so suites
/// that use one run side by side.
nonisolated struct CannedServer: Sendable {
    struct Answer: Sendable {
        var status: Int
        var body: Data
        var headers: [String: String] = [:]
    }

    let host = "\(UUID().uuidString.lowercased()).test"

    /// The live client pointed at this server.
    var api: LiveAPI {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedTransport.self]
        return LiveAPI(baseURL: URL(string: "https://\(host)").unsafelyUnwrapped, session: URLSession(configuration: configuration))
    }

    /// What the next requests are answered, in order; the last answer stays.
    func answer(_ answers: Answer...) {
        CannedTransport.lock.withLock { CannedTransport.answers[host] = answers }
    }

    func answer(_ status: Int, _ body: Data, headers: [String: String] = [:]) {
        answer(Answer(status: status, body: body, headers: headers))
    }

    func answer(_ status: Int, json: String, headers: [String: String] = [:]) {
        answer(status, Data(json.utf8), headers: headers)
    }

    /// The server's error shape.
    static func error(_ code: String, _ message: String) -> Data {
        Data(#"{"error":{"code":"\#(code)","message":"\#(message)"}}"#.utf8)
    }

    var requests: [(request: URLRequest, body: Data?)] {
        CannedTransport.lock.withLock { CannedTransport.seen[host] ?? [] }
    }
}

nonisolated private final class CannedTransport: URLProtocol, @unchecked Sendable {
    static let lock = NSLock()
    nonisolated(unsafe) static var answers: [String: [CannedServer.Answer]] = [:]
    nonisolated(unsafe) static var seen: [String: [(request: URLRequest, body: Data?)]] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody
        if body == nil, let stream = request.httpBodyStream {
            stream.open()
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                data.append(buffer, count: read)
            }
            stream.close()
            body = data
        }
        let host = request.url?.host() ?? ""
        let answer = Self.lock.withLock { () -> CannedServer.Answer in
            Self.seen[host, default: []].append((request, body))
            var queue = Self.answers[host] ?? []
            let next = queue.first ?? .init(status: 200, body: Data())
            if queue.count > 1 { queue.removeFirst() }
            Self.answers[host] = queue
            return next
        }
        let response = HTTPURLResponse(
            url: request.url.unsafelyUnwrapped, statusCode: answer.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"].merging(answer.headers) { _, new in new }
        ).unsafelyUnwrapped
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: answer.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: The transport

/// One transport carries every route: what it puts on the wire and how it
/// reads what comes back.
@Suite struct TransportTests {
    private let server = CannedServer()

    /// A check in a SAN path travels as "%2B" in the request itself, whatever the route.
    @Test func aPlusInAQueryIsPercentEncodedOnTheWire() async throws {
        server.answer(200, json: #"{"ok":true}"#)
        let _: OkResponse = try await server.api.send(
            "GET", "explorer/position", query: [URLQueryItem(name: "path", value: "e4,e5,Bb5+")], token: "abc"
        )
        let sent = try #require(server.requests.first?.request)
        #expect(sent.url?.query(percentEncoded: true) == "path=e4,e5,Bb5%2B")
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer abc")
        #expect(sent.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test func aRequestCarriesItsBodyAndItsOwnTimeout() async throws {
        server.answer(200, json: #"{"ok":true}"#)
        let api = server.api
        let _: OkResponse = try await api.send("PUT", "repertoires/r1/pgn", token: "abc", body: ImportRepertoirePgnRequest(pgn: "1. e4"), timeout: 60)
        let _: OkResponse = try await api.send("POST", "repertoires/r1/seed", token: "abc", timeout: 60)
        let _: OkResponse = try await api.send("GET", "courses")
        let sent = server.requests
        #expect(sent.map(\.request.timeoutInterval) == [60, 60, LiveAPI.standardTimeout])
        #expect(sent[0].request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try JSONSerialization.jsonObject(with: try #require(sent[0].body)) as? [String: String] == ["pgn": "1. e4"])
        #expect(sent[1].body?.isEmpty != false)
        #expect(sent[2].request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    /// 429 says how long to wait: the header is kept with the error.
    @Test func tooManyRequestsKeepTheServersWait() async throws {
        server.answer(429, CannedServer.error("rate_limited", "Too many attempts. Try again in a moment."), headers: ["Retry-After": "60"])
        do {
            let _: OkResponse = try await server.api.send("GET", "explorer/position", token: "abc")
            Issue.record("A 429 is an error.")
        } catch let failure as APIError {
            #expect(failure == .rateLimited(retryAfter: 60, message: "Too many attempts. Try again in a moment."))
            #expect(failure.isRateLimited)
            #expect(failure.code == "rate_limited")
            #expect(failure.retryAfter == 60)
            #expect(failure.message == "Too many attempts. Try again in a minute.")
        }
        // Without the header, the server's own sentence.
        let bare: APIError = .rateLimited(retryAfter: nil, message: "Too many attempts. Try again in a moment.")
        #expect(bare.message == "Too many attempts. Try again in a moment.")
        #expect(APIError.rateLimited(retryAfter: 12, message: nil).message == "Too many attempts. Try again in 12 seconds.")
        #expect(APIError.rateLimited(retryAfter: 300, message: nil).message == "Too many attempts. Try again in 5 minutes.")
    }

    /// 409 and 422 share a code; the status tells a lost write from a refusal.
    @Test func aLostWriteIsToldFromARefusal() async throws {
        server.answer(
            .init(status: 409, body: CannedServer.error("request_failed", "The repertoire was changed at the same time. Try again.")),
            .init(status: 422, body: CannedServer.error("request_failed", "That move is not legal in this position."))
        )
        var failures: [APIError] = []
        for _ in 0..<2 {
            do {
                _ = try await server.api.addRepertoireLine(id: "r1", line: ["e2e4"], token: "abc")
            } catch let failure as APIError {
                failures.append(failure)
            }
        }
        #expect(failures.map(\.isConflict) == [true, false])
        #expect(failures.map(\.code) == ["request_failed", "request_failed"])
        #expect(failures.last?.message == "That move is not legal in this position.")
    }
}
