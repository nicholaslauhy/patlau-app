import SwiftUI

enum AttendanceReportRange: String, CaseIterable, Identifiable {
    case selectedDay = "Selected day"
    case allRecords = "All records"

    var id: String { rawValue }
}

enum AttendanceReportStatusFilter: String, CaseIterable, Identifiable {
    case all = "All statuses"
    case attended = "Attended"
    case missed = "Missed"
    case makeup = "Makeup"

    var id: String { rawValue }

    var status: AttendanceStatus? {
        switch self {
        case .all: nil
        case .attended: .attended
        case .missed: .missed
        case .makeup: .makeup
        }
    }
}

struct SessionAttendanceReportEntry: Identifiable, Equatable {
    let id: String
    let programme: Programme
    let dateKey: String
    let sessionKey: String
    let sessionTitle: String
    let studentKey: String
    let studentName: String
    let status: AttendanceStatus
    let recordedAt: String
    let detail: String?

    var latestKey: String {
        [programme.rawValue, dateKey, sessionKey, studentKey]
            .joined(separator: "|")
    }
}

struct SessionAttendanceReportSection: Identifiable, Equatable {
    let dateKey: String
    let sessionKey: String
    let sessionTitle: String
    let entries: [SessionAttendanceReportEntry]

    var id: String { "\(dateKey)|\(sessionKey)" }
}

private struct SessionAttendanceReportDateGroup: Identifiable {
    let dateKey: String
    let sections: [SessionAttendanceReportSection]

    var id: String { dateKey }
}

enum SessionAttendanceReportBuilder {
    static func entries(
        programme: Programme,
        students: [DynamicRecord],
        attendanceRecords: [DynamicRecord] = [],
        sessions: [DynamicRecord] = [],
        coaches: [DynamicRecord] = []
    ) -> [SessionAttendanceReportEntry] {
        let rawEntries: [SessionAttendanceReportEntry]
        switch programme {
        case .weekend:
            rawEntries = weekendEntries(students: students)
        case .weekday:
            rawEntries = tableEntries(
                programme: .weekday,
                students: students,
                attendanceRecords: attendanceRecords,
                studentIDKey: "weekday_student_id"
            )
        case .matchplay:
            rawEntries = tableEntries(
                programme: .matchplay,
                students: students,
                attendanceRecords: attendanceRecords,
                studentIDKey: "matchplay_student_id"
            )
        case .oneToOne:
            rawEntries = oneToOneEntries(
                students: students,
                sessions: sessions,
                coaches: coaches
            )
        }

        // A session report should show one current result per student. If a
        // legacy table contains duplicate actions for the same session, retain
        // the most recently updated action rather than repeating the student.
        let latest = rawEntries.reduce(into: [String: SessionAttendanceReportEntry]()) {
            current, entry in
            guard let existing = current[entry.latestKey] else {
                current[entry.latestKey] = entry
                return
            }
            if entry.recordedAt >= existing.recordedAt {
                current[entry.latestKey] = entry
            }
        }

        return latest.values.sorted(by: entrySort)
    }

    static func sections(
        from entries: [SessionAttendanceReportEntry]
    ) -> [SessionAttendanceReportSection] {
        Dictionary(grouping: entries) { "\($0.dateKey)|\($0.sessionKey)" }
            .compactMap { _, values in
                guard let first = values.first else { return nil }
                return SessionAttendanceReportSection(
                    dateKey: first.dateKey,
                    sessionKey: first.sessionKey,
                    sessionTitle: first.sessionTitle,
                    entries: values.sorted {
                        $0.studentName.localizedCaseInsensitiveCompare($1.studentName) == .orderedAscending
                    }
                )
            }
            .sorted {
                if $0.dateKey != $1.dateKey { return $0.dateKey > $1.dateKey }
                return $0.sessionTitle.localizedCaseInsensitiveCompare($1.sessionTitle) == .orderedAscending
            }
    }

    private static func weekendEntries(
        students: [DynamicRecord]
    ) -> [SessionAttendanceReportEntry] {
        students.flatMap { student in
            let studentID = student.values.text("student_id", fallback: student.id)
            let name = student.values.text("student_name", fallback: "Student")
            let day = student.values.text("student_day", fallback: "Weekend")
            let timeslot = student.values.text("student_timeslot", fallback: "Session")
            let sessionTitle = [day, timeslot]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            let sessionKey = "\(day.lowercased())|\(timeslot.lowercased())"

            return (student.values["attendance_records"]?.array ?? [])
                .enumerated()
                .compactMap { index, value -> SessionAttendanceReportEntry? in
                    guard let rawValue = value.string else { return nil }
                    let parts = rawValue
                        .split(separator: "|", omittingEmptySubsequences: false)
                        .map(String.init)
                    guard let dateKey = dateKey(from: parts.first ?? rawValue),
                          let status = status(from: parts.count > 1 ? parts[1] : "attended"),
                          status != .scheduled else {
                        return nil
                    }

                    let target = parts.count > 3
                        ? parts[3].replacingOccurrences(of: "_", with: " ").capitalized
                        : ""
                    let detail = status == .makeup && !target.isEmpty
                        ? "Makeup programme: \(target)"
                        : nil

                    return SessionAttendanceReportEntry(
                        id: "weekend|\(studentID)|\(index)|\(rawValue)",
                        programme: .weekend,
                        dateKey: dateKey,
                        sessionKey: sessionKey,
                        sessionTitle: sessionTitle.isEmpty ? "Weekend session" : sessionTitle,
                        studentKey: studentID,
                        studentName: name,
                        status: status,
                        recordedAt: parts.first ?? rawValue,
                        detail: detail
                    )
                }
        }
    }

    private static func tableEntries(
        programme: Programme,
        students: [DynamicRecord],
        attendanceRecords: [DynamicRecord],
        studentIDKey: String
    ) -> [SessionAttendanceReportEntry] {
        let studentsByID = recordLookup(students)

        return attendanceRecords.compactMap { attendance in
            let studentID = attendance.values.text(studentIDKey)
            guard !studentID.isEmpty,
                  let dateKey = dateKey(from: attendance.values.text("attendance_date")),
                  let status = status(from: attendance.values.text("status")),
                  status != .scheduled else {
                return nil
            }

            let student = studentsByID[studentID]
            let name = student?.values.text("student_name", fallback: "Student")
                ?? attendance.values.text("student_name", fallback: "Student")
            let recordedAt = attendance.values.text(
                "updated_at",
                fallback: attendance.values.text("created_at", fallback: dateKey)
            )

            let sessionKey: String
            let sessionTitle: String
            let detail: String?
            if programme == .weekday {
                let day = attendance.values.text("day_name", fallback: "Weekday")
                let duration = attendance.values.number("duration_hours")
                let durationLabel = duration > 0 ? " • \(numberLabel(duration))h" : ""
                sessionKey = "\(day.lowercased())|\(numberLabel(duration))h"
                sessionTitle = "\(day)\(durationLabel) session"
                detail = duration > 0 ? "Duration: \(numberLabel(duration)) hours" : nil
            } else {
                sessionKey = "matchplay"
                sessionTitle = "MatchPlay session"
                detail = nil
            }

            return SessionAttendanceReportEntry(
                id: "\(programme.rawValue)|\(attendance.id)",
                programme: programme,
                dateKey: dateKey,
                sessionKey: sessionKey,
                sessionTitle: sessionTitle,
                studentKey: studentID,
                studentName: name,
                status: status,
                recordedAt: recordedAt,
                detail: detail
            )
        }
    }

    private static func oneToOneEntries(
        students: [DynamicRecord],
        sessions: [DynamicRecord],
        coaches: [DynamicRecord]
    ) -> [SessionAttendanceReportEntry] {
        let studentsByID = recordLookup(students)
        let coachesByID = recordLookup(coaches)

        return sessions.compactMap { session in
            let rawStatus = session.values.text("attendance_status", fallback: "scheduled")
            guard let status = status(from: rawStatus), status != .scheduled,
                  let dateKey = dateKey(from: session.values.text("session_date")) else {
                return nil
            }

            let studentID = session.values.text("student_id")
            let coachID = session.values.text("coach_id")
            let studentName = session.values.text(
                "student_name",
                fallback: studentsByID[studentID]?.values.text("student_name", fallback: "Student")
                    ?? "Student"
            )
            let coachName = session.values.text(
                "coach_name",
                fallback: displayName(coachesByID[coachID])
            )
            let recordedAt = session.values.text(
                "attendance_updated_at",
                fallback: session.values.text("updated_at", fallback: dateKey)
            )

            return SessionAttendanceReportEntry(
                id: "oneToOne|\(session.id)",
                programme: .oneToOne,
                dateKey: dateKey,
                sessionKey: "one-to-one",
                sessionTitle: "1-1 Training",
                studentKey: studentID.isEmpty ? session.id : studentID,
                studentName: studentName,
                status: status,
                recordedAt: recordedAt,
                detail: coachName.isEmpty ? nil : "Coach: \(coachName)"
            )
        }
    }

    private static func recordLookup(
        _ records: [DynamicRecord]
    ) -> [String: DynamicRecord] {
        records.reduce(into: [:]) { result, record in
            result[record.id] = record
            for key in ["student_id", "auth_user_id", "user_id"] {
                let value = record.values.text(key)
                if !value.isEmpty { result[value] = record }
            }
        }
    }

    private static func displayName(_ record: DynamicRecord?) -> String {
        guard let record else { return "" }
        if let metadata = record.values["user_metadata"]?.object {
            let name = metadata.text("name")
            if !name.isEmpty { return name }
        }
        return record.values.text(
            "name",
            fallback: record.values.text("email", fallback: "Coach")
        )
    }

    private static func dateKey(from rawValue: String) -> String? {
        let prefix = String(rawValue.prefix(10))
        guard prefix.count == 10,
              prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
              prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-" else {
            return nil
        }
        return prefix
    }

    private static func status(from rawValue: String) -> AttendanceStatus? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "mark", "attended", "present": .attended
        case "missed", "absent": .missed
        case "makeup", "make-up": .makeup
        case "scheduled", "undo": .scheduled
        default: nil
        }
    }

    private static func numberLabel(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.1f", value)
    }

    private static func entrySort(
        _ lhs: SessionAttendanceReportEntry,
        _ rhs: SessionAttendanceReportEntry
    ) -> Bool {
        if lhs.dateKey != rhs.dateKey { return lhs.dateKey > rhs.dateKey }
        if lhs.sessionTitle != rhs.sessionTitle {
            return lhs.sessionTitle.localizedCaseInsensitiveCompare(rhs.sessionTitle) == .orderedAscending
        }
        return lhs.studentName.localizedCaseInsensitiveCompare(rhs.studentName) == .orderedAscending
    }
}

struct SessionAttendanceReportView: View {
    @EnvironmentObject private var state: AppState

    let programme: Programme

    @State private var range: AttendanceReportRange = .selectedDay
    @State private var selectedDate = Date()
    @State private var statusFilter: AttendanceReportStatusFilter = .all
    @State private var search = ""
    @State private var entries: [SessionAttendanceReportEntry] = []
    @State private var loading = false

    private var filteredEntries: [SessionAttendanceReportEntry] {
        entries.filter { entry in
            let dateMatches = range == .allRecords || entry.dateKey == selectedDate.isoDateKey
            let statusMatches = statusFilter.status == nil || entry.status == statusFilter.status
            let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let searchMatches = trimmedSearch.isEmpty
                || [entry.studentName, entry.sessionTitle, entry.detail ?? "", entry.status.reportTitle]
                    .joined(separator: " ")
                    .localizedCaseInsensitiveContains(trimmedSearch)
            return dateMatches && statusMatches && searchMatches
        }
    }

    private var sections: [SessionAttendanceReportSection] {
        SessionAttendanceReportBuilder.sections(from: filteredEntries)
    }

    private var loadKey: String {
        range == .selectedDay
            ? "\(programme.rawValue)|selected|\(selectedDate.isoDateKey)"
            : "\(programme.rawValue)|all"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                reportHeader

                Picker("Report range", selection: $range) {
                    ForEach(AttendanceReportRange.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("attendance-report-range")

                if range == .selectedDay {
                    HStack(spacing: 12) {
                        Button {
                            changeDate(by: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Previous day")

                        DatePicker(
                            "Report date",
                            selection: $selectedDate,
                            displayedComponents: .date
                        )
                        .datePickerStyle(.compact)

                        Button {
                            changeDate(by: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .frame(width: 36, height: 36)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Next day")
                    }
                    .appCard(padding: 12)
                }

                summaryGrid

                AppSearchField(
                    prompt: "Search student or session",
                    text: $search
                )

                HStack(spacing: 12) {
                    Menu {
                        Picker("Status", selection: $statusFilter) {
                            ForEach(AttendanceReportStatusFilter.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                    } label: {
                        Label(
                            statusFilter.rawValue,
                            systemImage: "line.3.horizontal.decrease.circle"
                        )
                        .font(.subheadline.weight(.semibold))
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityLabel("Attendance status filter")

                    Spacer()

                    Text("\(filteredEntries.count) record\(filteredEntries.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)

                    DataRefreshButton(scope: "\(programme.title) session reports") {
                        await load()
                    }
                }

                if sections.isEmpty && !loading {
                    EmptyState(
                        icon: "list.clipboard",
                        title: "No attendance recorded",
                        message: range == .selectedDay
                            ? "No students have been marked for this date and filter."
                            : "No recorded attendance matches this filter."
                    )
                } else {
                    reportSections
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("Session Reports")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task(id: loadKey) { await load() }
        .overlay {
            if loading { LoadingOverlay(text: "Loading session reports") }
        }
    }

    private var reportHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: programme.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.colour(for: programme))
                .frame(width: 44, height: 44)
                .background(
                    Theme.colour(for: programme).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 12)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("\(programme.title) Attendance Report")
                    .font(.headline)
                Text("Students are grouped by attendance date and session.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)
        }
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            summaryCard("Recorded", count: filteredEntries.count, color: Theme.blue, icon: "person.2.fill")
            summaryCard("Attended", count: count(.attended), color: Theme.green, icon: "checkmark.circle.fill")
            summaryCard("Missed", count: count(.missed), color: Theme.red, icon: "xmark.circle.fill")
            summaryCard("Makeup", count: count(.makeup), color: Theme.amber, icon: "arrow.triangle.2.circlepath")
        }
        .accessibilityIdentifier("attendance-report-summary")
    }

    private func summaryCard(
        _ title: String,
        count: Int,
        color: Color,
        icon: String
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(count)")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 0)
        }
        .appCard(padding: 12)
    }

    private var reportSections: some View {
        ForEach(groupedDates) { dateGroup in
            VStack(alignment: .leading, spacing: 10) {
                Text(reportDateTitle(dateGroup.dateKey))
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)

                ForEach(dateGroup.sections) { section in
                    VStack(spacing: 0) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.sessionTitle)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            Text("\(section.entries.count) student\(section.entries.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(Theme.background.opacity(0.75))

                        ForEach(Array(section.entries.enumerated()), id: \.element.id) { index, entry in
                            if index > 0 { Divider().padding(.leading, 54) }
                            reportRow(entry)
                        }
                    }
                    .appCard(padding: 0)
                    .accessibilityIdentifier("attendance-report-session-\(section.id)")
                }
            }
        }
    }

    private var groupedDates: [SessionAttendanceReportDateGroup] {
        Dictionary(grouping: sections, by: \.dateKey)
            .map {
                SessionAttendanceReportDateGroup(
                    dateKey: $0.key,
                    sections: $0.value
                )
            }
            .sorted { $0.dateKey > $1.dateKey }
    }

    private func reportRow(_ entry: SessionAttendanceReportEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.status.reportIcon)
                .font(.body.weight(.semibold))
                .foregroundStyle(entry.status.reportColor)
                .frame(width: 30, height: 30)
                .background(entry.status.reportColor.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.studentName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                if let time = reportTime(entry.recordedAt) {
                    Text("Recorded \(time)")
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            Spacer(minLength: 8)

            StatusBadge(text: entry.status.reportTitle, color: entry.status.reportColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .accessibilityIdentifier("attendance-report-entry-\(entry.id)")
    }

    private func count(_ status: AttendanceStatus) -> Int {
        filteredEntries.filter { $0.status == status }.count
    }

    private func changeDate(by days: Int) {
        selectedDate = Calendar.current.date(
            byAdding: .day,
            value: days,
            to: selectedDate
        ) ?? selectedDate
    }

    private func reportDateTitle(_ dateKey: String) -> String {
        guard let parsed = Self.dateParser.date(from: dateKey) else { return dateKey }
        return parsed.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    private func reportTime(_ rawValue: String) -> String? {
        guard rawValue.count > 10 else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let parsed = formatter.date(from: rawValue)
            ?? ISO8601DateFormatter().date(from: rawValue)
        return parsed?.formatted(.dateTime.hour().minute())
    }

    private func load() async {
        loading = true
        defer { loading = false }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingSessionReports") {
            entries = Self.fixtureEntries(dateKey: selectedDate.isoDateKey, programme: programme)
            return
        }
#endif

        do {
            switch programme {
            case .weekend:
                let students = try await BackendClient.shared.weekendStudents(
                    path: WeekendStudentWebsiteRoute.attendance
                )
                entries = SessionAttendanceReportBuilder.entries(
                    programme: .weekend,
                    students: students
                )

            case .weekday, .matchplay:
                let attendanceTable = programme.attendanceTable ?? ""
                async let loadedStudents = BackendClient.shared.select(
                    table: programme.studentTable,
                    query: [.init(name: "order", value: "student_name.asc")]
                )
                async let loadedAttendance = BackendClient.shared.select(
                    table: attendanceTable,
                    query: attendanceQuery()
                )
                entries = try await SessionAttendanceReportBuilder.entries(
                    programme: programme,
                    students: loadedStudents,
                    attendanceRecords: loadedAttendance
                )

            case .oneToOne:
                async let loadedStudents = BackendClient.shared.select(
                    table: "one_to_one_students",
                    query: [.init(name: "order", value: "student_name.asc")]
                )
                async let loadedSessions = BackendClient.shared.select(
                    table: "one_to_one_sessions",
                    query: oneToOneQuery()
                )
                let usersResponse = try? await BackendClient.shared.websiteJSON(
                    path: "/api/users/list"
                )
                let coaches = usersResponse?.object?["users"]?.array?
                    .compactMap(\.object)
                    .map(DynamicRecord.init) ?? []
                entries = try await SessionAttendanceReportBuilder.entries(
                    programme: .oneToOne,
                    students: loadedStudents,
                    sessions: loadedSessions,
                    coaches: coaches
                )
            }
        } catch {
            state.show(error)
        }
    }

    private func attendanceQuery() -> [URLQueryItem] {
        var query = [URLQueryItem(name: "order", value: "attendance_date.desc")]
        if range == .selectedDay {
            query.insert(
                URLQueryItem(
                    name: "attendance_date",
                    value: "eq.\(selectedDate.isoDateKey)"
                ),
                at: 0
            )
        }
        return query
    }

    private func oneToOneQuery() -> [URLQueryItem] {
        var query = [URLQueryItem(name: "order", value: "session_date.desc")]
        if range == .selectedDay {
            let start = selectedDate.isoDateKey
            let end = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)?
                .isoDateKey ?? start
            query.insert(.init(name: "session_date", value: "lt.\(end)"), at: 0)
            query.insert(.init(name: "session_date", value: "gte.\(start)"), at: 0)
        }
        return query
    }

    private static let dateParser: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func fixtureEntries(
        dateKey: String,
        programme: Programme
    ) -> [SessionAttendanceReportEntry] {
        [
            SessionAttendanceReportEntry(
                id: "fixture-attended",
                programme: programme,
                dateKey: dateKey,
                sessionKey: "fixture-session",
                sessionTitle: programme == .weekend ? "Saturday • 2-4pm" : "Morning session",
                studentKey: "fixture-brendan",
                studentName: "Brendan Lau",
                status: .attended,
                recordedAt: "\(dateKey)T08:30:00Z",
                detail: programme == .oneToOne ? "Coach: Patrick Lau" : nil
            ),
            SessionAttendanceReportEntry(
                id: "fixture-missed",
                programme: programme,
                dateKey: dateKey,
                sessionKey: "fixture-session",
                sessionTitle: programme == .weekend ? "Saturday • 2-4pm" : "Morning session",
                studentKey: "fixture-nicholas",
                studentName: "Nicholas Lau",
                status: .missed,
                recordedAt: "\(dateKey)T08:35:00Z",
                detail: nil
            )
        ]
    }
}

private extension AttendanceStatus {
    var reportTitle: String {
        switch self {
        case .scheduled: "Scheduled"
        case .attended: "Attended"
        case .missed: "Missed"
        case .makeup: "Makeup"
        }
    }

    var reportIcon: String {
        switch self {
        case .scheduled: "calendar.badge.clock"
        case .attended: "checkmark.circle.fill"
        case .missed: "xmark.circle.fill"
        case .makeup: "arrow.triangle.2.circlepath"
        }
    }

    var reportColor: Color {
        switch self {
        case .scheduled: Theme.secondaryText
        case .attended: Theme.green
        case .missed: Theme.red
        case .makeup: Theme.amber
        }
    }
}
