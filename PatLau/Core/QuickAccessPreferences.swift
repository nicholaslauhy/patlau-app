import Foundation

enum QuickAccessPreferences {
    static let maximumCount = 5

    static let defaults: [PortalOperation] = [
        .weekendAttendance,
        .weekendDashboard,
        .coachAttendance,
        .oneToOneTraining,
        .myAttendance
    ]

    static func decode(_ value: String, for role: UserRole) -> [PortalOperation] {
        guard !value.isEmpty,
              let data = value.data(using: .utf8),
              let rawValues = try? JSONDecoder().decode([String].self, from: data) else {
            return normalized(defaults, for: role)
        }

        return normalized(rawValues.compactMap(PortalOperation.init(rawValue:)), for: role)
    }

    static func encode(_ operations: [PortalOperation], for role: UserRole) -> String {
        let values = normalized(operations, for: role).map(\.rawValue)
        let data = (try? JSONEncoder().encode(values)) ?? Data("[]".utf8)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    static func normalized(
        _ operations: [PortalOperation],
        for role: UserRole
    ) -> [PortalOperation] {
        var seen: Set<PortalOperation> = []
        return operations.filter { operation in
            operation.isAvailable(for: role) && seen.insert(operation).inserted
        }
        .prefix(maximumCount)
        .map { $0 }
    }
}
