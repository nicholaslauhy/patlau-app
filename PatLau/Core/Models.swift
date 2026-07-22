import Foundation

enum UserRole: String, Codable, CaseIterable, Hashable, Sendable {
    case superuser
    case admin
    case member

    var displayName: String {
        switch self {
        case .superuser: "Superuser"
        case .admin: "Admin"
        case .member: "Member"
        }
    }

    var permissionRank: Int {
        switch self {
        case .member: 0
        case .admin: 1
        case .superuser: 2
        }
    }
}

struct AuthUser: Codable, Sendable {
    let id: String
    let email: String?
    let userMetadata: JSONObject?
    let appMetadata: JSONObject?

    enum CodingKeys: String, CodingKey {
        case id, email
        case userMetadata = "user_metadata"
        case appMetadata = "app_metadata"
    }

    var name: String {
        userMetadata?.text("name", fallback: email ?? "User") ?? email ?? "User"
    }

    /// Metadata is only a temporary UI fallback. AppState resolves the current
    /// protected role through the database after every sign-in and restoration.
    var role: UserRole {
        if let value = appMetadata?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }

        if let value = userMetadata?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }

        return .member
    }

    var avatarURL: URL? {
        guard let value = userMetadata?.text("avatar_url"), !value.isEmpty else { return nil }
        return URL(string: value)
    }

    func replacingRole(_ role: UserRole) -> AuthUser {
        var metadata = appMetadata ?? [:]
        metadata["role"] = .string(role.rawValue)
        return AuthUser(
            id: id,
            email: email,
            userMetadata: userMetadata,
            appMetadata: metadata
        )
    }
}

struct AuthSession: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let expiresAt: Double?
    let tokenType: String?
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case expiresAt = "expires_at"
        case tokenType = "token_type"
        case user
    }

    var expiryDate: Date? {
        if let expiresAt { return Date(timeIntervalSince1970: expiresAt) }

        // `expires_in` is relative to the instant the server issued the token. It
        // cannot safely be applied to `Date()` after a session has been restored
        // from Keychain because doing so would make an expired token look fresh
        // again. Supabase access tokens carry the absolute expiry in their JWT.
        let parts = accessToken.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count > 1 else { return nil }

        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload.append(String(repeating: "=", count: (4 - payload.count % 4) % 4))

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONDecoder().decode(JSONObject.self, from: data),
              let expiration = object["exp"]?.double else {
            return nil
        }
        return Date(timeIntervalSince1970: expiration)
    }

    func replacingUser(_ user: AuthUser) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresIn: expiresIn,
            expiresAt: expiresAt,
            tokenType: tokenType,
            user: user
        )
    }
}

struct LoginEnvelope: Codable {
    let session: AuthSession
    let user: AuthUser?
}

struct ResetVerificationEnvelope: Codable {
    let session: AuthSession
}

enum Programme: String, CaseIterable, Identifiable, Hashable, Sendable {
    case weekend
    case weekday
    case matchplay
    case oneToOne

    var id: String { rawValue }

    var title: String {
        switch self {
        case .oneToOne: "1-1"
        case .matchplay: "MatchPlay"
        default: rawValue.prefix(1).uppercased() + String(rawValue.dropFirst())
        }
    }

    var icon: String {
        switch self {
        case .weekend: "calendar"
        case .weekday: "calendar.badge.clock"
        case .matchplay: "figure.badminton"
        case .oneToOne: "person.2.fill"
        }
    }

    var studentTable: String {
        switch self {
        case .weekend: "students"
        case .weekday: "weekday_students"
        case .matchplay: "matchplay_students"
        case .oneToOne: "one_to_one_students"
        }
    }

    /// Weekend mirrors the legacy website table, where current students are
    /// represented by the rows themselves rather than an `active` column.
    var activeStudentFilter: URLQueryItem? {
        guard self != .weekend else { return nil }
        return URLQueryItem(
            name: "or",
            value: "(active.is.null,active.eq.true)"
        )
    }

    func includesStudent(active: Bool?) -> Bool {
        self == .weekend || active != false
    }

    var attendanceTable: String? {
        switch self {
        case .weekend: nil
        case .weekday: "weekday_attendance"
        case .matchplay: "matchplay_attendance"
        case .oneToOne: "one_to_one_sessions"
        }
    }

    var paymentTable: String {
        switch self {
        case .weekend: "payment_history"
        case .weekday: "weekday_payments"
        case .matchplay: "matchplay_payments"
        case .oneToOne: "training_payments"
        }
    }
}

enum AttendanceStatus: String, CaseIterable, Hashable, Sendable {
    case scheduled
    case attended
    case missed
    case makeup
}

enum PaymentFilter: String, CaseIterable {
    case all
    case paid
    case unpaid
}

struct WeekdayMonthlyPaymentSummary: Equatable, Sendable {
    let sessionCount: Int
    let payableHours: Double
    let amount: Double
}

enum WeekdayMonthlyPaymentCalculator {
    static let scheduledDays = ["Monday", "Wednesday", "Thursday"]

    static func occurrences(
        of day: String,
        in month: Date,
        calendar: Calendar = .current
    ) -> Int {
        let weekdayNumbers = [
            "Sunday": 1,
            "Monday": 2,
            "Tuesday": 3,
            "Wednesday": 4,
            "Thursday": 5,
            "Friday": 6,
            "Saturday": 7
        ]
        guard let target = weekdayNumbers[day],
              let interval = calendar.dateInterval(of: .month, for: month) else {
            return 0
        }

        var count = 0
        var date = interval.start
        while date < interval.end {
            if calendar.component(.weekday, from: date) == target {
                count += 1
            }
            date = calendar.date(byAdding: .day, value: 1, to: date)
                ?? interval.end
        }
        return count
    }

    static func summary(
        schedules: [JSONObject],
        hourlyRate: Double,
        month: Date,
        manualHoursByDay: [String: Double] = [:],
        calendar: Calendar = .current
    ) -> WeekdayMonthlyPaymentSummary {
        var sessionCount = 0
        var payableHours = 0.0

        for schedule in schedules {
            let day = schedule.text("day")
            let occurrences = occurrences(
                of: day,
                in: month,
                calendar: calendar
            )
            let duration = schedule.number(
                "duration_hours",
                fallback: schedule.number("duration", fallback: 1)
            )
            sessionCount += occurrences
            payableHours += manualHoursByDay[day]
                ?? duration * Double(occurrences)
        }

        return WeekdayMonthlyPaymentSummary(
            sessionCount: sessionCount,
            payableHours: payableHours,
            amount: payableHours * hourlyRate
        )
    }
}
