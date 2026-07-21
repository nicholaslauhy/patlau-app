import Foundation

enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    var string: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): value ? "true" : "false"
        default: nil
        }
    }

    var double: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    var bool: Bool? {
        switch self {
        case .bool(let value): value
        case .string(let value): Bool(value)
        default: nil
        }
    }

    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
    var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
}

typealias JSONObject = [String: JSONValue]

extension Dictionary where Key == String, Value == JSONValue {
    func text(_ key: String, fallback: String = "") -> String { self[key]?.string ?? fallback }
    func number(_ key: String, fallback: Double = 0) -> Double { self[key]?.double ?? fallback }
    func flag(_ key: String, fallback: Bool = false) -> Bool { self[key]?.bool ?? fallback }
}

struct DynamicRecord: Identifiable, Sendable {
    let values: JSONObject
    let id: String

    init(values: JSONObject) {
        self.values = values
        id = Self.resolveID(in: values)
    }

    func matches(_ search: String) -> Bool {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !term.isEmpty else { return true }
        return values.values.compactMap(\.string).joined(separator: " ").lowercased().contains(term)
    }

    private static func resolveID(in values: JSONObject) -> String {
        // Prefer true row identifiers when the backend provides one.
        for key in [
            "id", "conversation_id", "session_id", "payment_id",
            "attendance_id", "credit_id", "usage_id", "vote_id"
        ] {
            let value = values.text(key)
            if !value.isEmpty { return value }
        }

        // Some legacy payment/attendance tables have no `id`. Those tables can
        // contain several rows for one student, so using only `student_id` makes
        // SwiftUI treat separate rows as duplicates. Build a stable composite
        // identity from the row's reference and date instead.
        let isRepeatedRow = values["amount"] != nil
            || values["paid"] != nil
            || values["status"] != nil
            || values["response"] != nil
        if isRepeatedRow {
            let components = [
                "student_id", "weekday_student_id", "matchplay_student_id",
                "training_student_id", "recorded_at", "week_date",
                "payment_month", "attendance_date", "session_date",
                "date_key", "slot_key", "created_at"
            ].compactMap { key -> String? in
                let value = values.text(key)
                return value.isEmpty ? nil : "\(key)=\(value)"
            }
            if !components.isEmpty { return components.joined(separator: "|") }
        }

        // Entity records use these values as backend identifiers elsewhere in
        // the app, so keep their raw value rather than adding a display prefix.
        for key in ["auth_user_id", "telegram_chat_id", "student_id"] {
            let value = values.text(key)
            if !value.isEmpty { return value }
        }

        // Store the fallback once. The previous computed UUID changed on every
        // access, which destabilised List/ForEach rendering and navigation.
        return UUID().uuidString
    }
}
