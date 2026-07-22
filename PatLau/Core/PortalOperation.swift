import Foundation

enum AppTab: Hashable {
    case home
    case operations
    case account
}

enum OperationGroup: String, CaseIterable, Identifiable, Hashable {
    case weekend
    case weekday
    case matchplay
    case oneToOne
    case makeup
    case support
    case account

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekend: "Weekend"
        case .weekday: "Weekday"
        case .matchplay: "MatchPlay"
        case .oneToOne: "1-1 Training"
        case .makeup: "Makeup"
        case .support: "Support & Attendance"
        case .account: "Account"
        }
    }

    var icon: String {
        switch self {
        case .weekend: "calendar"
        case .weekday: "calendar.badge.clock"
        case .matchplay: "figure.badminton"
        case .oneToOne: "person.2.fill"
        case .makeup: "arrow.triangle.2.circlepath"
        case .support: "bubble.left.and.bubble.right.fill"
        case .account: "person.crop.circle"
        }
    }
}

enum AppRoute: Hashable {
    case group(OperationGroup)
    case operation(PortalOperation)
}

/// A one-to-one map of the authenticated operational areas exposed by the
/// PatLau website. Each route opens its mobile-native SwiftUI equivalent.
enum PortalOperation: String, CaseIterable, Identifiable, Hashable {
    case weekendDashboard
    case weekendAddStudent
    case weekendAttendance
    case weekendAttendanceReport
    case weekendPayment
    case coachAttendance

    case weekdayDashboard
    case weekdayAddStudent
    case weekdayAttendance
    case weekdayAttendanceReport
    case weekdayPayment

    case matchplayOverview
    case matchplayAddStudent
    case matchplayAttendance
    case matchplayAttendanceReport
    case matchplayPayment

    case oneToOneDashboard
    case oneToOneAddStudent
    case oneToOneTraining
    case oneToOneAttendanceReport
    case oneToOnePayment

    case makeupCredits
    case makeupPayment

    case chats
    case auditLogs
    case myAttendance
    case allAttendance
    case settings

    var id: String { rawValue }

    var group: OperationGroup {
        switch self {
        case .weekendDashboard, .weekendAddStudent, .weekendAttendance,
             .weekendAttendanceReport,
             .weekendPayment, .coachAttendance:
            .weekend
        case .weekdayDashboard, .weekdayAddStudent, .weekdayAttendance,
             .weekdayAttendanceReport, .weekdayPayment:
            .weekday
        case .matchplayOverview, .matchplayAddStudent, .matchplayAttendance,
             .matchplayAttendanceReport, .matchplayPayment:
            .matchplay
        case .oneToOneDashboard, .oneToOneAddStudent, .oneToOneTraining,
             .oneToOneAttendanceReport, .oneToOnePayment:
            .oneToOne
        case .makeupCredits, .makeupPayment:
            .makeup
        case .chats, .auditLogs, .myAttendance, .allAttendance:
            .support
        case .settings:
            .account
        }
    }

    var title: String {
        switch self {
        case .weekendDashboard: "Weekend Dashboard"
        case .weekendAddStudent: "Add Weekend Student"
        case .weekendAttendance: "Weekend Attendance"
        case .weekendAttendanceReport: "Weekend Session Reports"
        case .weekendPayment: "Weekend Payments"
        case .coachAttendance: "Coach Attendance Poll"
        case .weekdayDashboard: "Weekday Dashboard"
        case .weekdayAddStudent: "Add Weekday Student"
        case .weekdayAttendance: "Weekday Attendance"
        case .weekdayAttendanceReport: "Weekday Session Reports"
        case .weekdayPayment: "Weekday Payments"
        case .matchplayOverview: "MatchPlay Dashboard"
        case .matchplayAddStudent: "Add MatchPlay Student"
        case .matchplayAttendance: "MatchPlay Attendance"
        case .matchplayAttendanceReport: "MatchPlay Session Reports"
        case .matchplayPayment: "MatchPlay Payments"
        case .oneToOneDashboard: "1-1 Student Dashboard"
        case .oneToOneAddStudent: "Add 1-1 Student"
        case .oneToOneTraining: "1-1 Training & Attendance"
        case .oneToOneAttendanceReport: "1-1 Session Reports"
        case .oneToOnePayment: "1-1 Payments"
        case .makeupCredits: "My Makeup"
        case .makeupPayment: "Makeup Payments"
        case .chats: "Parent Support Chats"
        case .auditLogs: "Audit Logs"
        case .myAttendance: "My Coaching Attendance"
        case .allAttendance: "All Attendance"
        case .settings: "Settings"
        }
    }

    var subtitle: String {
        switch self {
        case .weekendDashboard: "Manage student details, pricing and course settings"
        case .weekendAddStudent: "Create a new weekend training record"
        case .weekendAttendance: "Mark attended, missed or makeup and undo the latest action"
        case .weekendAttendanceReport: "Review recorded students by date and Weekend session"
        case .weekendPayment: "Review and record weekend payments"
        case .coachAttendance: "Send the Telegram availability poll to coaches"
        case .weekdayDashboard: "View and manage Weekday students"
        case .weekdayAddStudent: "Create weekday schedules and hourly rates"
        case .weekdayAttendance: "Record attendance by weekday session"
        case .weekdayAttendanceReport: "Review recorded students by date and Weekday session"
        case .weekdayPayment: "Review monthly weekday payments"
        case .matchplayOverview: "Open the MatchPlay management hub"
        case .matchplayAddStudent: "Create a MatchPlay training record"
        case .matchplayAttendance: "Record MatchPlay attendance and makeups"
        case .matchplayAttendanceReport: "Review recorded students for each MatchPlay session"
        case .matchplayPayment: "Review MatchPlay payment records"
        case .oneToOneDashboard: "View and manage 1-1 students"
        case .oneToOneAddStudent: "Add a student to the 1-1 programme"
        case .oneToOneTraining: "Add or remove pairs and update 1-1 attendance"
        case .oneToOneAttendanceReport: "Review 1-1 results with student and coach details"
        case .oneToOnePayment: "Review 1-1 training payments"
        case .makeupCredits: "Track available credits, recent usage and credit history"
        case .makeupPayment: "Manage makeup top-up payments"
        case .chats: "Handle escalations, replies and chatbot information"
        case .auditLogs: "Review security, activity and data-change records"
        case .myAttendance: "View your own coaching attendance history"
        case .allAttendance: "Review attendance across all coaches"
        case .settings: "Profile, password and user administration"
        }
    }

    var directoryTitle: String {
        switch self {
        case .weekendDashboard, .weekdayDashboard, .matchplayOverview,
             .oneToOneDashboard: "Dashboard"
        case .weekendAddStudent, .weekdayAddStudent, .matchplayAddStudent,
             .oneToOneAddStudent: "Add Student"
        case .weekendAttendance, .weekdayAttendance, .matchplayAttendance: "Attendance"
        case .weekendAttendanceReport, .weekdayAttendanceReport,
             .matchplayAttendanceReport, .oneToOneAttendanceReport: "Session Reports"
        case .weekendPayment, .weekdayPayment, .matchplayPayment,
             .oneToOnePayment, .makeupPayment: "Payment"
        case .coachAttendance: "Coach Attendance"
        case .oneToOneTraining: "Training & Attendance"
        case .makeupCredits: "My Makeup"
        case .chats: "Chats"
        case .auditLogs: "Audit Logs"
        case .myAttendance: "My Attendance"
        case .allAttendance: "All Attendance"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .weekendDashboard, .weekdayDashboard, .matchplayOverview,
             .oneToOneDashboard:
            "rectangle.grid.1x2.fill"
        case .weekendAddStudent, .weekdayAddStudent, .matchplayAddStudent,
             .oneToOneAddStudent:
            "person.badge.plus"
        case .weekendAttendance, .weekdayAttendance, .matchplayAttendance:
            "checkmark.circle.fill"
        case .weekendAttendanceReport, .weekdayAttendanceReport,
             .matchplayAttendanceReport, .oneToOneAttendanceReport:
            "list.clipboard.fill"
        case .weekendPayment, .weekdayPayment, .matchplayPayment,
             .oneToOnePayment, .makeupPayment:
            "dollarsign.circle.fill"
        case .coachAttendance:
            "paperplane.fill"
        case .oneToOneTraining:
            "calendar.badge.checkmark"
        case .makeupCredits:
            "ticket.fill"
        case .chats:
            "bubble.left.and.bubble.right.fill"
        case .auditLogs:
            "list.clipboard.fill"
        case .myAttendance:
            "person.crop.circle.badge.checkmark"
        case .allAttendance:
            "person.3.sequence.fill"
        case .settings:
            "gearshape.fill"
        }
    }

    var webPath: String {
        switch self {
        // The deployed website names these routes from the opposite point of
        // view: `/dashboard` is the day-to-day attendance workflow, while
        // `/attendance` is the superuser student/course editor.
        case .weekendDashboard: "/attendance"
        case .weekendAddStudent: "/add"
        case .weekendAttendance: "/dashboard"
        case .weekendAttendanceReport: "/app/weekend/session-reports"
        case .weekendPayment: "/payment"
        case .coachAttendance: "/coachattendance"
        case .weekdayDashboard: "/weekday"
        case .weekdayAddStudent: "/weekday/add"
        case .weekdayAttendance: "/weekday/attendance"
        case .weekdayAttendanceReport: "/app/weekday/session-reports"
        case .weekdayPayment: "/weekday/payment"
        case .matchplayOverview: "/matchplay"
        case .matchplayAddStudent: "/matchplay/add"
        case .matchplayAttendance: "/matchplay/attendance"
        case .matchplayAttendanceReport: "/app/matchplay/session-reports"
        case .matchplayPayment: "/matchplay/payment"
        case .oneToOneDashboard: "/training/students"
        case .oneToOneAddStudent: "/training/add"
        case .oneToOneTraining: "/training"
        case .oneToOneAttendanceReport: "/app/training/session-reports"
        case .oneToOnePayment: "/trngpayment"
        case .makeupCredits: "/makeup"
        case .makeupPayment: "/makeup/payment"
        case .chats: "/chats"
        case .auditLogs: "/audit-logs"
        case .myAttendance: "/myattendance"
        case .allAttendance: "/allattendance"
        case .settings: "/settings"
        }
    }

    var webURL: URL {
        URL(string: webPath, relativeTo: AppConfiguration.websiteURL)?.absoluteURL
            ?? AppConfiguration.websiteURL
    }

    var allowedRoles: Set<UserRole> {
        switch self {
        case .weekendAttendance, .weekendAttendanceReport, .myAttendance, .settings:
            [.member, .admin, .superuser]
        case .weekendAddStudent, .oneToOneAddStudent, .oneToOneTraining,
             .oneToOneAttendanceReport, .coachAttendance:
            [.admin, .superuser]
        default:
            [.superuser]
        }
    }

    func isAvailable(for role: UserRole) -> Bool {
        allowedRoles.contains(role)
    }

    static func visible(
        for role: UserRole,
        in group: OperationGroup? = nil
    ) -> [PortalOperation] {
        allCases.filter { operation in
            operation.isAvailable(for: role)
                && (group == nil || operation.group == group)
        }
    }

    /// Attendance reports that should always be visible on Home. These are
    /// intentionally independent of the user's customizable Quick Access list.
    static func homeAttendance(for role: UserRole) -> [PortalOperation] {
        [PortalOperation.myAttendance, .allAttendance].filter {
            $0.isAvailable(for: role)
        }
    }
}
