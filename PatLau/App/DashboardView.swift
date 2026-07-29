import SwiftUI

enum OperationsCommandSummaryError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The operations service returned an invalid summary."
    }
}

struct OperationsCommandSummary: Equatable {
    struct Weekend: Equatable {
        let totalStudents: Int
        let saturdayStudents: Int
        let sundayStudents: Int
        let completedCourses: Int
        let todayLessonDay: String?
        let todayScheduled: Int
        let todayRecorded: Int
        let todayRemaining: Int
    }

    struct Management: Equatable {
        let activeOneToOneStudents: Int
        let upcomingOneToOneSessions: Int
        let activeCoachPolls: Int
        let upcomingSaturdayCoaches: Int?
        let upcomingSundayCoaches: Int?
    }

    struct Superuser: Equatable {
        let outstandingWeekendPayments: Int
        let escalatedParentChats: Int
        let unreadParentMessages: Int
        let activeWeekdayStudents: Int
        let activeMatchPlayStudents: Int
        let availableMakeupCredits: Int
        let unpaidMakeupStudents: Int?
    }

    let role: UserRole
    let todayLabel: String
    let weekend: Weekend
    let management: Management?
    let superuser: Superuser?
    let warnings: [String]

    init(response: JSONValue) throws {
        guard let object = response.object,
              let role = UserRole(rawValue: object.text("role")),
              let weekendObject = object["weekend"]?.object else {
            throw OperationsCommandSummaryError.invalidResponse
        }

        self.role = role
        todayLabel = object.text("todayLabel")
        weekend = Weekend(
            totalStudents: Int(weekendObject.number("totalStudents")),
            saturdayStudents: Int(weekendObject.number("saturdayStudents")),
            sundayStudents: Int(weekendObject.number("sundayStudents")),
            completedCourses: Int(weekendObject.number("completedCourses")),
            todayLessonDay: weekendObject.text("todayLessonDay").nilIfEmpty,
            todayScheduled: Int(weekendObject.number("todayScheduled")),
            todayRecorded: Int(weekendObject.number("todayRecorded")),
            todayRemaining: Int(weekendObject.number("todayRemaining"))
        )

        if let managementObject = object["management"]?.object {
            management = Management(
                activeOneToOneStudents: Int(
                    managementObject.number("activeOneToOneStudents")
                ),
                upcomingOneToOneSessions: Int(
                    managementObject.number("upcomingOneToOneSessions")
                ),
                activeCoachPolls: Int(
                    managementObject.number("activeCoachPolls")
                ),
                upcomingSaturdayCoaches: managementObject[
                    "upcomingSaturdayCoaches"
                ]?.double.map(Int.init),
                upcomingSundayCoaches: managementObject[
                    "upcomingSundayCoaches"
                ]?.double.map(Int.init)
            )
        } else {
            management = nil
        }

        if let superuserObject = object["superuser"]?.object {
            superuser = Superuser(
                outstandingWeekendPayments: Int(
                    superuserObject.number("outstandingWeekendPayments")
                ),
                escalatedParentChats: Int(
                    superuserObject.number("escalatedParentChats")
                ),
                unreadParentMessages: Int(
                    superuserObject.number("unreadParentMessages")
                ),
                activeWeekdayStudents: Int(
                    superuserObject.number("activeWeekdayStudents")
                ),
                activeMatchPlayStudents: Int(
                    superuserObject.number("activeMatchPlayStudents")
                ),
                availableMakeupCredits: Int(
                    superuserObject.number("availableMakeupCredits")
                ),
                unpaidMakeupStudents: superuserObject[
                    "unpaidMakeupStudents"
                ]?.double.map(Int.init)
            )
        } else {
            superuser = nil
        }

        warnings = object["warnings"]?.array?.compactMap(\.string) ?? []
    }

#if DEBUG
    static let uiTestResponse = JSONValue.object([
        "role": .string("superuser"),
        "todayLabel": .string("Wednesday, 29 July 2026"),
        "weekend": .object([
            "totalStudents": .number(8),
            "saturdayStudents": .number(3),
            "sundayStudents": .number(5),
            "completedCourses": .number(2),
            "todayLessonDay": .null,
            "todayScheduled": .number(0),
            "todayRecorded": .number(0),
            "todayRemaining": .number(0)
        ]),
        "management": .object([
            "activeOneToOneStudents": .number(4),
            "upcomingOneToOneSessions": .number(3),
            "activeCoachPolls": .number(1),
            "upcomingSaturdayCoaches": .number(5),
            "upcomingSundayCoaches": .number(4)
        ]),
        "superuser": .object([
            "outstandingWeekendPayments": .number(2),
            "escalatedParentChats": .number(1),
            "unreadParentMessages": .number(5),
            "activeWeekdayStudents": .number(6),
            "activeMatchPlayStudents": .number(7),
            "availableMakeupCredits": .number(9),
            "unpaidMakeupStudents": .number(3)
        ]),
        "warnings": .array([])
    ])
#endif
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

struct DashboardView: View {
    @EnvironmentObject private var state: AppState

    let onOpenGroup: (OperationGroup) -> Void
    let onOpen: (PortalOperation) -> Void

    @State private var summary: OperationsCommandSummary?
    @State private var summaryError: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                welcomeCard

                if let summaryError {
                    summaryErrorCard(summaryError)
                }

                if let summary {
                    ForEach(summary.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.amber)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                    }
                }

                if state.role == .superuser {
                    attentionSection
                }

                programmePortfolioSection

                if state.role == .superuser {
                    makeupSummarySection
                }

                weekendReadinessSection

                if state.role == .admin || state.role == .superuser {
                    managementSection
                }

                if !homeAttendanceOperations.isEmpty {
                    SectionHeading(
                        title: "Attendance",
                        subtitle: state.role == .superuser
                            ? "View your coaching history or review attendance across every coach."
                            : "View your own coaching attendance history."
                    )

                    VStack(spacing: 0) {
                        ForEach(
                            Array(homeAttendanceOperations.enumerated()),
                            id: \.element
                        ) { index, operation in
                            Button {
                                onOpen(operation)
                            } label: {
                                OperationRow(operation: operation)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)

                            if index < homeAttendanceOperations.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .appCard(padding: 0)
                    .accessibilityIdentifier("home-attendance-section")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("Home")
        .refreshable {
            await load()
        }
        .task(id: state.role) { await load() }
    }

    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                UserAvatarView(
                    url: state.user?.avatarURL,
                    role: state.role,
                    size: 52,
                    revision: state.avatarRevision,
                    tint: Theme.blue
                )

                VStack(alignment: .leading, spacing: 5) {
                    Text("COMMAND CENTRE")
                        .font(.caption2.weight(.bold))
                        .tracking(0.8)
                        .foregroundStyle(Theme.blue)
                    Text("Welcome back, \(state.user?.name ?? "User")")
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(roleDescription)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                StatusBadge(
                    text: roleViewLabel,
                    color: Theme.blue
                )

                if let dateLabel = summary?.todayLabel, !dateLabel.isEmpty {
                    Text(dateLabel)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                } else if loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Loading operations summary")
                }

                Spacer(minLength: 6)

                DataRefreshButton(scope: "operations summary") {
                    await load()
                }
            }

            if state.isResolvingRole {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("Checking account access")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .appCard()
        .accessibilityIdentifier("operations-command-centre")
    }

    @ViewBuilder
    private var weekendReadinessSection: some View {
        SectionHeading(
            title: "Weekend attendance readiness",
            subtitle: "See the current roster and whether today’s attendance is complete."
        )

        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ],
            spacing: 12
        ) {
            summaryMetric(
                title: "Weekend students",
                value: summaryValue(summary?.weekend.totalStudents),
                detail: "Current roster",
                icon: "person.3.fill",
                color: Theme.blue,
                operation: .weekendAttendance
            )
            summaryMetric(
                title: "Saturday roster",
                value: summaryValue(summary?.weekend.saturdayStudents),
                detail: "Saturday students",
                icon: "calendar",
                color: Theme.purple
            )
            summaryMetric(
                title: "Sunday roster",
                value: summaryValue(summary?.weekend.sundayStudents),
                detail: "Sunday students",
                icon: "sun.max.fill",
                color: Theme.green
            )
            summaryMetric(
                title: "Completed courses",
                value: summaryValue(summary?.weekend.completedCourses),
                detail: "Lessons fully used",
                icon: "checkmark.seal.fill",
                color: Theme.secondaryText
            )
        }

        Button {
            onOpen(.weekendAttendance)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(
                    systemName: summary?.weekend.todayLessonDay == nil
                        ? "info.circle.fill"
                        : "checkmark.circle.fill"
                )
                .font(.title3)
                .foregroundStyle(
                    summary?.weekend.todayLessonDay == nil
                        ? Theme.blue
                        : Theme.green
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(weekendTodayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(weekendTodayDetail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                if let weekend = summary?.weekend,
                   weekend.todayLessonDay != nil {
                    VStack(spacing: 1) {
                        Text("\(weekend.todayRemaining)")
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(Theme.ink)
                        Text("remaining")
                            .font(.caption2)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appCard()
    }

    @ViewBuilder
    private var programmePortfolioSection: some View {
        SectionHeading(
            title: "Programme portfolio",
            subtitle: "Open a programme to access its available tools."
        )

        VStack(spacing: 0) {
            ForEach(
                Array(visiblePortfolioGroups.enumerated()),
                id: \.element.id
            ) { index, group in
                Button {
                    onOpenGroup(group)
                } label: {
                    programmePortfolioRow(group)
                        .padding(.horizontal, 16)
                }
                .buttonStyle(.plain)

                if index < visiblePortfolioGroups.count - 1 {
                    Divider()
                        .padding(.leading, 70)
                }
            }
        }
        .appCard(padding: 0)
    }

    @ViewBuilder
    private var makeupSummarySection: some View {
        SectionHeading(
            title: "Makeup",
            subtitle: "Track credits and outstanding makeup payments."
        )

        VStack(spacing: 0) {
            summaryActionRow(
                title: "Available makeup credits",
                value: summaryValue(summary?.superuser?.availableMakeupCredits),
                detail: "Credit history and programme transfers",
                icon: "ticket.fill",
                color: Theme.amber,
                operation: .makeupCredits
            )

            Divider()
                .padding(.leading, 70)

            summaryActionRow(
                title: "Unpaid makeup students",
                value: summaryValue(summary?.superuser?.unpaidMakeupStudents),
                detail: "Distinct students this month",
                icon: "person.crop.circle.badge.exclamationmark",
                color: Theme.red,
                operation: .makeupPayment
            )
        }
        .appCard(padding: 0)
        .accessibilityIdentifier("home-makeup-summary")
    }

    @ViewBuilder
    private var managementSection: some View {
        SectionHeading(
            title: "Weekend Coach Coordination",
            subtitle: "Upcoming 1-1 sessions and coaches attending the next Weekend shifts."
        )

        VStack(spacing: 0) {
            summaryActionRow(
                title: "Upcoming 1-1 sessions",
                value: summaryValue(summary?.management?.upcomingOneToOneSessions),
                detail: "Next seven days",
                icon: "calendar.badge.checkmark",
                color: Theme.teal,
                operation: .oneToOneTraining
            )

            Divider()
                .padding(.leading, 70)

            summaryActionRow(
                title: "Coming Saturday",
                value: summaryValue(
                    summary?.management?.upcomingSaturdayCoaches
                ),
                detail: "Coaches attending",
                icon: "paperplane.fill",
                color: Theme.purple,
                operation: .coachAttendance
            )

            Divider()
                .padding(.leading, 70)

            summaryActionRow(
                title: "Coming Sunday",
                value: summaryValue(
                    summary?.management?.upcomingSundayCoaches
                ),
                detail: "Coaches attending",
                icon: "paperplane.fill",
                color: Theme.blue,
                operation: .coachAttendance
            )
        }
        .appCard(padding: 0)
    }

    @ViewBuilder
    private var attentionSection: some View {
        SectionHeading(
            title: "Needs attention",
            subtitle: "Superuser follow-ups from payments and parent support."
        )

        VStack(spacing: 0) {
            summaryActionRow(
                title: "Weekend unpaid",
                value: summaryValue(
                    summary?.superuser?.outstandingWeekendPayments
                ),
                detail: "Outstanding students",
                icon: "dollarsign.circle.fill",
                color: Theme.amber,
                operation: .weekendPayment
            )

            Divider()
                .padding(.leading, 70)

            summaryActionRow(
                title: "Escalated chats",
                value: summaryValue(summary?.superuser?.escalatedParentChats),
                detail: "Waiting for a reply",
                icon: "bubble.left.and.exclamationmark.bubble.right.fill",
                color: Theme.teal,
                operation: .chats
            )

            Divider()
                .padding(.leading, 70)

            summaryActionRow(
                title: "Unread messages",
                value: summaryValue(summary?.superuser?.unreadParentMessages),
                detail: "Across parent chats",
                icon: "envelope.badge.fill",
                color: Theme.purple,
                operation: .chats
            )
        }
        .appCard(padding: 0)
    }

    private var roleViewLabel: String {
        switch state.role {
        case .superuser: "Superuser"
        case .admin: "Admin"
        case .member: "Member"
        }
    }

    private var roleDescription: String {
        switch state.role {
        case .superuser:
            "Review cross-programme work, payments, support, attendance and administrative follow-ups."
        case .admin:
            "Open Weekend attendance, student, coach-attendance and 1-1 workflows."
        case .member:
            "Open Weekend attendance and your own coaching records without administrative controls."
        }
    }

    private var weekendTodayTitle: String {
        guard let weekend = summary?.weekend else {
            return loading ? "Loading Weekend readiness…" : "Weekend readiness unavailable"
        }
        guard let day = weekend.todayLessonDay else {
            return "No Weekend roster scheduled today"
        }
        return "\(day) attendance"
    }

    private var weekendTodayDetail: String {
        guard let weekend = summary?.weekend else {
            return "Pull down or use Refresh to try again."
        }
        guard weekend.todayLessonDay != nil else {
            return "Prepare the next session or review an earlier attendance report."
        }
        return "\(weekend.todayRecorded) of \(weekend.todayScheduled) students have an attendance record today."
    }

    private func summaryErrorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .foregroundStyle(Theme.red)

            VStack(alignment: .leading, spacing: 5) {
                Text("Operations summary unavailable")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button("Try Again") {
                Task { await load() }
            }
            .buttonStyle(.plain)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.blue)
            .touchTarget()
        }
        .appCard()
    }

    @ViewBuilder
    private func summaryMetric(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color,
        operation: PortalOperation? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        if let action {
            Button(action: action) {
                OperationsSummaryMetric(
                    title: title,
                    value: value,
                    detail: detail,
                    icon: icon,
                    color: color,
                    isLink: true
                )
            }
            .buttonStyle(.plain)
        } else if let operation {
            Button {
                onOpen(operation)
            } label: {
                OperationsSummaryMetric(
                    title: title,
                    value: value,
                    detail: detail,
                    icon: icon,
                    color: color,
                    isLink: true
                )
            }
            .buttonStyle(.plain)
        } else {
            OperationsSummaryMetric(
                title: title,
                value: value,
                detail: detail,
                icon: icon,
                color: color,
                isLink: false
            )
        }
    }

    private var visiblePortfolioGroups: [OperationGroup] {
        [.weekend, .weekday, .matchplay, .oneToOne].filter {
            !PortalOperation.visible(for: state.role, in: $0).isEmpty
        }
    }

    private func programmePortfolioRow(
        _ group: OperationGroup
    ) -> some View {
        HStack(spacing: 14) {
            Image(systemName: group.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.colour(for: group))
                .frame(width: 40, height: 40)
                .background(
                    Theme.colour(for: group).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(group == .oneToOne ? "1-1" : group.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(
                    PortalOperation.visible(for: state.role, in: group)
                        .map(\.directoryTitle)
                        .joined(separator: " • ")
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func summaryActionRow(
        title: String,
        value: String,
        detail: String,
        icon: String,
        color: Color,
        operation: PortalOperation
    ) -> some View {
        Button {
            onOpen(operation)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 40, height: 40)
                    .background(
                        color.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 11)
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Text(value)
                    .font(.title3.bold().monospacedDigit())
                    .foregroundStyle(Theme.ink)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func summaryValue(_ value: Int?) -> String {
        value.map(String.init) ?? "—"
    }

    private var homeAttendanceOperations: [PortalOperation] {
        PortalOperation.homeAttendance(for: state.role)
    }

    private func load() async {
        loading = summary == nil
        defer { loading = false }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains(
            "-uiTestingOperationsSummary"
        ) {
            summary = try? OperationsCommandSummary(
                response: OperationsCommandSummary.uiTestResponse
            )
            summaryError = nil
            return
        }
#endif

        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "/api/operations/summary"
            )
            summary = try OperationsCommandSummary(response: response)
            summaryError = nil
        } catch {
            summaryError = error.localizedDescription
        }
    }
}

private struct OperationsSummaryMetric: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let color: Color
    let isLink: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                    .frame(width: 32, height: 32)
                    .background(
                        color.opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 9)
                    )

                Spacer(minLength: 6)

                if isLink {
                    Image(systemName: "arrow.up.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(color)
                }
            }

            Text(value)
                .font(.title2.bold().monospacedDigit())
                .foregroundStyle(Theme.ink)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .appCard(padding: 13)
        .contentShape(Rectangle())
    }
}

struct QuickAccessEditor: View {
    @Environment(\.dismiss) private var dismiss

    let role: UserRole
    let onSave: ([PortalOperation]) -> Void

    @State private var selected: [PortalOperation]

    init(
        role: UserRole,
        initialSelection: [PortalOperation],
        onSave: @escaping ([PortalOperation]) -> Void
    ) {
        self.role = role
        self.onSave = onSave
        _selected = State(
            initialValue: QuickAccessPreferences.normalized(initialSelection, for: role)
        )
    }

    private var available: [PortalOperation] {
        PortalOperation.visible(for: role).filter { !selected.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Quick Access",
                    onCancel: { dismiss() },
                    actionTitle: "Save",
                    onAction: {
                        onSave(selected)
                        dismiss()
                    }
                )

                List {
                Section {
                    if selected.isEmpty {
                        Text("No shortcuts selected")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(selected) { operation in
                        Label(operation.title, systemImage: operation.icon)
                            .foregroundStyle(Theme.ink)
                    }
                    .onMove { source, destination in
                        selected.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        selected.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Your shortcuts (\(selected.count)/\(QuickAccessPreferences.maximumCount))")
                } footer: {
                    Text("Drag the handles to reorder. Swipe left or tap minus to remove.")
                }

                Section("Add a shortcut") {
                    if selected.count >= QuickAccessPreferences.maximumCount {
                        Text("Remove a shortcut before adding another.")
                            .foregroundStyle(Theme.secondaryText)
                    } else if available.isEmpty {
                        Text("All available operations are selected.")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(available) { operation in
                            Button {
                                guard selected.count < QuickAccessPreferences.maximumCount else { return }
                                selected.append(operation)
                            } label: {
                                HStack {
                                    Label(operation.title, systemImage: operation.icon)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.blue)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                }
                }
                .environment(\.editMode, .constant(.active))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
