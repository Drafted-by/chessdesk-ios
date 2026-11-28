import Foundation

/// Everything the app asks the ChessDesk backend. Screens depend on this
/// protocol, never on URLSession: the live client and the fixture client are
/// interchangeable, which is what previews, tests and offline Debug builds use.
///
/// `token` is nil for a guest. Guest-open routes answer without it.
nonisolated protocol ChessDeskAPI: Sendable {
    func login(email: String, password: String) async throws -> AuthSession
    /// A player account. Coaches sign up on the site.
    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession
    /// Signs in, or creates the account, from a Sign in with Apple identity token.
    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession
    func resendVerification(token: String) async throws
    /// Deletes the account for good. The password when it has one; an Apple
    /// authorisation code when there is one, so Apple is told too.
    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws
    /// Presents a StoreKit transaction; the server verifies Apple's signature
    /// and answers with the account's access.
    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me
    func refresh(token: String) async throws -> AuthSession
    func me(token: String) async throws -> Me

    func courses(token: String?) async throws -> [CourseCard]
    func course(slug: String, token: String?) async throws -> CourseDetail
    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession
    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws
    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int

    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws
    func due(token: String) async throws -> DueSummary

    func paths(token: String?) async throws -> [PathCard]
    func path(slug: String, token: String?) async throws -> PathDetail
    /// The exercises of a stage; nil asks for the next stage to do.
    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession
    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int
}

nonisolated enum APICoding {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an ISO 8601 date: \(text)")
            )
        }
        return decoder
    }()

    static let encoder = JSONEncoder()

    /// The server writes JavaScript ISO strings, with milliseconds.
    static func parseDate(_ text: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        return (try? withFraction.parse(text)) ?? (try? Date.ISO8601FormatStyle().parse(text))
    }
}

/// The live client: bearer token, JSON in and out, one error shape.
nonisolated struct LiveAPI: ChessDeskAPI {
    let baseURL: URL
    var session: URLSession = .shared

    func login(email: String, password: String) async throws -> AuthSession {
        try await send("POST", "auth/login", body: LoginRequest(email: email, password: password))
    }

    func signup(firstName: String, lastName: String, email: String, password: String) async throws -> AuthSession {
        try await send(
            "POST", "auth/signup",
            body: SignupRequest(firstName: firstName, lastName: lastName, email: email, password: password)
        )
    }

    func signInWithApple(identityToken: String, firstName: String?, lastName: String?) async throws -> AuthSession {
        try await send(
            "POST", "auth/apple",
            body: AppleSignInRequest(identityToken: identityToken, firstName: firstName, lastName: lastName)
        )
    }

    func resendVerification(token: String) async throws {
        let _: OkResponse = try await send("POST", "auth/verification", token: token)
    }

    func deleteAccount(currentPassword: String?, appleAuthorizationCode: String?, token: String) async throws {
        let _: OkResponse = try await send(
            "DELETE", "me", token: token,
            body: DeleteAccountRequest(currentPassword: currentPassword, appleAuthorizationCode: appleAuthorizationCode)
        )
    }

    func recordApplePurchase(signedTransaction: String, token: String) async throws -> Me {
        try await send(
            "POST", "purchases/apple", token: token,
            body: ApplePurchaseRequest(signedTransaction: signedTransaction)
        )
    }

    func refresh(token: String) async throws -> AuthSession {
        try await send("POST", "auth/refresh", token: token)
    }

    func me(token: String) async throws -> Me {
        try await send("GET", "me", token: token)
    }

    func courses(token: String?) async throws -> [CourseCard] {
        let response: CoursesResponse = try await send("GET", "courses", token: token)
        return response.courses
    }

    func course(slug: String, token: String?) async throws -> CourseDetail {
        try await send("GET", "courses/\(slug)", token: token)
    }

    func courseSession(slug: String, mode: SessionMode, line: String?, token: String?) async throws -> CourseSession {
        var query = [URLQueryItem(name: "mode", value: mode.rawValue)]
        if let line { query.append(URLQueryItem(name: "line", value: line)) }
        return try await send("GET", "courses/\(slug)/session", query: query, token: token)
    }

    func setEnrollment(slug: String, status: EnrollmentStatus, token: String) async throws {
        let _: OkResponse = try await send(
            "PUT", "courses/\(slug)/enrollment", token: token, body: EnrollmentRequest(status: status)
        )
    }

    func importLocalProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int {
        let result: LocalProgressResult = try await send(
            "POST", "courses/\(slug)/local-progress", token: token, body: LocalProgressRequest(grades: grades)
        )
        return result.imported
    }

    func sendGrades(deck: String, grades: [MoveGrade], token: String) async throws {
        let _: OkResponse = try await send(
            "POST", "training/grades", token: token, body: GradesRequest(deck: deck, grades: grades)
        )
    }

    func due(token: String) async throws -> DueSummary {
        try await send("GET", "training/due", token: token)
    }

    func paths(token: String?) async throws -> [PathCard] {
        let response: PathsResponse = try await send("GET", "paths", token: token)
        return response.paths
    }

    func path(slug: String, token: String?) async throws -> PathDetail {
        try await send("GET", "paths/\(slug)", token: token)
    }

    func pathSession(slug: String, stage: String?, token: String?) async throws -> PathSession {
        let query = stage.map { [URLQueryItem(name: "stage", value: $0)] } ?? []
        return try await send("GET", "paths/\(slug)/session", query: query, token: token)
    }

    func importLocalPathProgress(slug: String, grades: [MoveGrade], token: String) async throws -> Int {
        let result: LocalProgressResult = try await send(
            "POST", "paths/\(slug)/local-progress", token: token, body: LocalProgressRequest(grades: grades)
        )
        return result.imported
    }

    // MARK: Transport

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        token: String? = nil
    ) async throws -> Response {
        try await perform(request(method, path, query: query, token: token))
    }

    private func send<Response: Decodable>(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        token: String? = nil,
        body: some Encodable
    ) async throws -> Response {
        var request = request(method, path, query: query, token: token)
        request.httpBody = try APICoding.encoder.encode(body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try await perform(request)
    }

    func request(_ method: String, _ path: String, query: [URLQueryItem], token: String?) -> URLRequest {
        var url = baseURL.appending(path: "api/v1").appending(path: path)
        if !query.isEmpty { url.append(queryItems: query) }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func perform<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw APIError.offline
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.unreadable }
        return try Self.decode(status: http.statusCode, data: data)
    }

    static func decode<Response: Decodable>(status: Int, data: Data) throws -> Response {
        guard (200..<300).contains(status) else {
            if let body = try? APICoding.decoder.decode(APIErrorBody.self, from: data) {
                throw APIError.server(status: status, code: body.error.code, message: body.error.message)
            }
            throw APIError.unreadable
        }
        do {
            return try APICoding.decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.unreadable
        }
    }
}
