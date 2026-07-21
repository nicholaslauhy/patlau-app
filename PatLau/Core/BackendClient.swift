import Foundation

enum WeekendStudentWebsiteRoute {
    static let dashboard = "/api/search"
    static let attendance = "/api/attendance-search"
    static let payments = "/api/payment-search"

    /// Both routes read the same legacy Weekend `students` records. Some
    /// deployments of the dashboard search route still apply an obsolete
    /// `active` filter, so fall back to the payment search route that is
    /// already used successfully by Weekend Payments.
    static let dashboardSources = [dashboard, payments]
}

enum BackendError: LocalizedError {
    case message(String)
    case http(status: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .message(let value):
            value
        case .http(let status, let message):
            message.isEmpty
                ? "\(status): \(HTTPURLResponse.localizedString(forStatusCode: status))"
                : "\(status): \(message)"
        }
    }

    var isUnauthorized: Bool {
        if case .http(let status, _) = self { return status == 401 }
        return false
    }
}

actor BackendClient {
    static let shared = BackendClient()

    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private var session: AuthSession?

    func setSession(_ value: AuthSession?) {
        session = value
    }

    func clearSession(ifAccessTokenMatches accessToken: String?) {
        guard accessToken == nil || session?.accessToken == accessToken else {
            return
        }
        session = nil
    }

    func currentSession() -> AuthSession? {
        session
    }

    func signIn(identifier: String, password: String) async throws -> AuthSession {
        let body: JSONObject = [
            "emailOrUsername": .string(identifier),
            "password": .string(password)
        ]
        let data = try await website(
            path: "/api/auth/login",
            method: "POST",
            body: body,
            authenticated: false
        )
        let envelope = try decoder.decode(LoginEnvelope.self, from: data)
        let signedInSession: AuthSession
        if let user = envelope.user, user.id == envelope.session.user.id {
            signedInSession = envelope.session.replacingUser(user)
        } else {
            signedInSession = envelope.session
        }
        session = signedInSession
        return signedInSession
    }

    func sendPasswordResetCode(email: String) async throws {
        _ = try await website(
            path: "/api/auth/send-reset-code",
            method: "POST",
            body: ["email": .string(email)],
            authenticated: false
        )
    }

    func verifyPasswordResetCode(email: String, code: String) async throws -> AuthSession {
        let data = try await website(
            path: "/api/auth/verify-reset-code",
            method: "POST",
            body: [
                "email": .string(email),
                "code": .string(code)
            ],
            authenticated: false
        )
        return try decoder.decode(ResetVerificationEnvelope.self, from: data).session
    }

    /// Completes the same reset flow used by the website, but keeps the
    /// recovery session native so the user enters the app after changing the
    /// password instead of being redirected to a browser page.
    func completePasswordReset(
        password: String,
        recoverySession: AuthSession
    ) async throws -> AuthSession {
        var request = URLRequest(url: websiteURL(path: "/api/auth/change-password"))
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(
            "Bearer \(recoverySession.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.httpBody = try encoder.encode(
            JSONValue.object(["password": .string(password)])
        )
        _ = try await perform(request)
        session = recoverySession
        return recoverySession
    }

    func refreshSession() async throws -> AuthSession {
        guard let refreshToken = session?.refreshToken else {
            throw BackendError.message("Please sign in again.")
        }

        let url = AppConfiguration.supabaseURL
            .appending(path: "/auth/v1/token")
            .appending(queryItems: [.init(name: "grant_type", value: "refresh_token")])

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue(AppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["refresh_token": refreshToken])

        let data = try await perform(request)
        let refreshed = try decoder.decode(AuthSession.self, from: data)
        session = refreshed
        return refreshed
    }

    func fetchCurrentUser() async throws -> AuthUser {
        let url = AppConfiguration.supabaseURL.appending(path: "/auth/v1/user")
        let request = try authenticatedRequest(url: url, method: "GET")
        let data = try await performWithRefresh(request)
        return try decoder.decode(AuthUser.self, from: data)
    }

    /// Reads the same protected role used by the website API and database policies.
    func currentRole() async throws -> UserRole {
        let value = try await rpc("current_app_role", params: [:])
        guard let rawValue = value.string,
              let role = UserRole(rawValue: rawValue) else {
            throw BackendError.message("The server returned an invalid account role.")
        }
        return role
    }

    func select(
        table: String,
        columns: String = "*",
        query: [URLQueryItem] = []
    ) async throws -> [DynamicRecord] {
        let data = try await rest(
            table: table,
            method: "GET",
            query: [.init(name: "select", value: columns)] + query
        )
        return try decoder.decode([JSONObject].self, from: data).map(DynamicRecord.init)
    }

    @discardableResult
    func insert(table: String, values: JSONObject) async throws -> [DynamicRecord] {
        let data = try await rest(
            table: table,
            method: "POST",
            body: .object(values),
            prefer: "return=representation"
        )
        return try decoder.decode([JSONObject].self, from: data).map(DynamicRecord.init)
    }

    @discardableResult
    func upsert(
        table: String,
        values: JSONObject,
        onConflict: String
    ) async throws -> [DynamicRecord] {
        let data = try await rest(
            table: table,
            method: "POST",
            query: [.init(name: "on_conflict", value: onConflict)],
            body: .object(values),
            prefer: "resolution=merge-duplicates,return=representation"
        )
        return try decoder.decode([JSONObject].self, from: data).map(DynamicRecord.init)
    }

    @discardableResult
    func update(
        table: String,
        values: JSONObject,
        filters: [URLQueryItem]
    ) async throws -> [DynamicRecord] {
        let data = try await rest(
            table: table,
            method: "PATCH",
            query: filters,
            body: .object(values),
            prefer: "return=representation"
        )
        return try decoder.decode([JSONObject].self, from: data).map(DynamicRecord.init)
    }

    func delete(table: String, filters: [URLQueryItem]) async throws {
        _ = try await rest(table: table, method: "DELETE", query: filters)
    }

    func rpc(_ name: String, params: JSONObject) async throws -> JSONValue {
        let url = AppConfiguration.supabaseURL.appending(path: "/rest/v1/rpc/\(name)")
        var request = try authenticatedRequest(url: url, method: "POST")
        request.httpBody = try encoder.encode(JSONValue.object(params))
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let data = try await performWithRefresh(request)
        return (try? decoder.decode(JSONValue.self, from: data)) ?? .null
    }

    func websiteJSON(
        path: String,
        method: String = "GET",
        body: JSONObject? = nil
    ) async throws -> JSONValue {
        let data = try await website(path: path, method: method, body: body, authenticated: true)
        return try decoder.decode(JSONValue.self, from: data)
    }

    func websiteData(
        path: String,
        method: String = "GET",
        body: JSONObject? = nil
    ) async throws -> Data {
        try await website(path: path, method: method, body: body, authenticated: true)
    }

    /// Weekend uses the website's legacy server-backed student source. Direct
    /// native REST reads can be hidden by the table's older row policies even
    /// though the same students remain visible on the website.
    func weekendStudents(path: String) async throws -> [DynamicRecord] {
        let response = try await websiteJSON(
            path: path,
            method: "POST",
            body: ["searchTerm": .string("%")]
        )
        guard let results = response.object?["results"]?.array else {
            throw BackendError.message(
                "The Weekend student service returned an invalid response."
            )
        }
        return results.compactMap(\.object).map(DynamicRecord.init(values:))
    }

    /// Loads legacy Weekend students from the first available website source.
    /// Authentication failures are not retried against another route, while a
    /// stale schema/query failure can transparently use the compatible source.
    func weekendStudents(paths: [String]) async throws -> [DynamicRecord] {
        guard !paths.isEmpty else {
            throw BackendError.message("No Weekend student service is configured.")
        }

        var lastError: Error?
        for path in paths {
            do {
                return try await weekendStudents(path: path)
            } catch let error as BackendError where error.isUnauthorized {
                throw error
            } catch {
                lastError = error
            }
        }

        throw lastError ?? BackendError.message(
            "The Weekend student service is unavailable."
        )
    }

    func updatePassword(_ password: String) async throws {
        let url = AppConfiguration.supabaseURL.appending(path: "/auth/v1/user")
        var request = try authenticatedRequest(url: url, method: "PUT")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(JSONValue.object(["password": .string(password)]))
        _ = try await performWithRefresh(request)
    }

    func uploadProfilePhoto(_ jpegData: Data) async throws -> JSONValue {
        let boundary = "PatLau-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"profile-photo.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpegData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = try authenticatedRequest(
            url: websiteURL(path: "/api/profile/photo"),
            method: "POST"
        )
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data = try await performWithRefresh(request)
        return try decoder.decode(JSONValue.self, from: data)
    }

    func deleteProfilePhoto() async throws {
        var request = try authenticatedRequest(
            url: websiteURL(path: "/api/profile/photo"),
            method: "DELETE"
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try await performWithRefresh(request)
    }

    private func rest(
        table: String,
        method: String,
        query: [URLQueryItem] = [],
        body: JSONValue? = nil,
        prefer: String? = nil
    ) async throws -> Data {
        let url = AppConfiguration.supabaseURL
            .appending(path: "/rest/v1/\(table)")
            .appending(queryItems: query)
        var request = try authenticatedRequest(url: url, method: method)

        if let body {
            request.httpBody = try encoder.encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let prefer {
            request.setValue(prefer, forHTTPHeaderField: "Prefer")
        }

        return try await performWithRefresh(request)
    }

    private func website(
        path: String,
        method: String,
        body: JSONObject?,
        authenticated: Bool
    ) async throws -> Data {
        var request = URLRequest(url: websiteURL(path: path))
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if authenticated, let token = session?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try encoder.encode(JSONValue.object(body))
        }

        return authenticated ? try await performWithRefresh(request) : try await perform(request)
    }

    private func websiteURL(path: String) -> URL {
        URL(string: path, relativeTo: AppConfiguration.websiteURL)?.absoluteURL
            ?? AppConfiguration.websiteURL
    }

    private func authenticatedRequest(url: URL, method: String) throws -> URLRequest {
        guard let token = session?.accessToken else {
            throw BackendError.message("Please sign in again.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 45
        request.setValue(AppConfiguration.supabasePublishableKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func performWithRefresh(_ request: URLRequest) async throws -> Data {
        do {
            return try await perform(request)
        } catch let error as BackendError where error.isUnauthorized {
            let refreshed = try await refreshSession()
            var retry = request
            retry.setValue("Bearer \(refreshed.accessToken)", forHTTPHeaderField: "Authorization")
            return try await perform(retry)
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BackendError.message("Invalid server response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            let object = try? decoder.decode(JSONObject.self, from: data)
            let message = object?.text(
                "error",
                fallback: object?.text("message") ?? ""
            ) ?? ""
            throw BackendError.http(status: http.statusCode, message: message)
        }

        return data.isEmpty ? Data("null".utf8) : data
    }
}
