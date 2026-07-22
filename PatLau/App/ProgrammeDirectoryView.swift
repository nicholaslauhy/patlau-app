import SwiftUI

struct ProgrammeDirectoryView: View {
    @EnvironmentObject private var state: AppState
    let group: OperationGroup

    private var operations: [PortalOperation] {
        PortalOperation.visible(for: state.role, in: group)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                Text("Choose a section")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.bottom, 4)

                VStack(spacing: 0) {
                    ForEach(Array(operations.enumerated()), id: \.element) { index, operation in
                        NavigationLink(value: AppRoute.operation(operation)) {
                            OperationRow(operation: operation)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)

                        if index < operations.count - 1 {
                            Divider().padding(.leading, 40)
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle(group.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativeOperationDestination: View {
    @EnvironmentObject private var state: AppState
    let operation: PortalOperation

    @ViewBuilder
    var body: some View {
        switch operation {
        case .weekendDashboard:
            StudentsView(initialProgramme: .weekend, showsProgrammePicker: false, title: "Weekend Dashboard")
        case .weekendAddStudent:
            AddStudentPage(programme: .weekend, showsDashboardAfterSave: state.role == .superuser)
        case .weekendAttendance:
            AttendanceView(initialProgramme: .weekend, showsProgrammePicker: false)
        case .weekendAttendanceReport:
            SessionAttendanceReportView(programme: .weekend)
        case .weekendPayment:
            PaymentsView(initialProgramme: .weekend, showsProgrammePicker: false)
        case .coachAttendance:
            CoachAttendanceView()
        case .weekdayDashboard:
            StudentsView(initialProgramme: .weekday, showsProgrammePicker: false, title: "Weekday Dashboard")
        case .weekdayAddStudent:
            AddStudentPage(programme: .weekday, showsDashboardAfterSave: state.role == .superuser)
        case .weekdayAttendance:
            AttendanceView(initialProgramme: .weekday, showsProgrammePicker: false)
        case .weekdayAttendanceReport:
            SessionAttendanceReportView(programme: .weekday)
        case .weekdayPayment:
            PaymentsView(initialProgramme: .weekday, showsProgrammePicker: false)
        case .matchplayOverview:
            StudentsView(initialProgramme: .matchplay, showsProgrammePicker: false, title: "MatchPlay Dashboard")
        case .matchplayAddStudent:
            AddStudentPage(programme: .matchplay, showsDashboardAfterSave: state.role == .superuser)
        case .matchplayAttendance:
            AttendanceView(initialProgramme: .matchplay, showsProgrammePicker: false)
        case .matchplayAttendanceReport:
            SessionAttendanceReportView(programme: .matchplay)
        case .matchplayPayment:
            PaymentsView(initialProgramme: .matchplay, showsProgrammePicker: false)
        case .oneToOneDashboard:
            StudentsView(initialProgramme: .oneToOne, showsProgrammePicker: false, title: "1-1 Student Dashboard")
        case .oneToOneAddStudent:
            AddStudentPage(programme: .oneToOne, showsDashboardAfterSave: state.role == .superuser)
        case .oneToOneTraining:
            TrainingView()
        case .oneToOneAttendanceReport:
            SessionAttendanceReportView(programme: .oneToOne)
        case .oneToOnePayment:
            PaymentsView(initialProgramme: .oneToOne, showsProgrammePicker: false)
        case .makeupCredits:
            MakeupView()
        case .makeupPayment:
            MakeupPaymentsView()
        case .chats:
            ChatsView()
        case .auditLogs:
            AuditLogsView()
        case .myAttendance:
            ReportsView(scope: .mine)
        case .allAttendance:
            ReportsView(scope: .all)
        case .settings:
            SettingsView()
        }
    }
}
