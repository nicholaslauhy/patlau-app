import SwiftUI

enum WeekendAttendancePolicy {
    static func attendedError(
        studentName: String,
        trainingDay: String,
        today: String
    ) -> String? {
        let resolvedName = studentName.isEmpty ? "This student" : studentName
        guard !trainingDay.isEmpty else {
            return "\(resolvedName) does not have a Weekend training day assigned. Update the student's schedule before marking attendance."
        }
        guard today == trainingDay else {
            return "\(resolvedName) is scheduled for \(trainingDay). Today is \(today), so Weekend attendance cannot be marked present yet."
        }
        return nil
    }
}

enum HistoricalAttendancePolicy {
    static func validationError(
        studentName: String,
        scheduledDays: [String],
        selectedDate: Date,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> String? {
        let name = studentName.isEmpty ? "This student" : studentName
        let selectedDay = selectedDate.formatted(.dateTime.weekday(.wide))

        if calendar.startOfDay(for: selectedDate) > calendar.startOfDay(for: now) {
            return "Attendance cannot be recorded for a future date."
        }
        guard !scheduledDays.isEmpty else {
            return "\(name) does not have a training day assigned. Update the student's schedule before recording attendance."
        }
        guard scheduledDays.contains(selectedDay) else {
            let schedule = ListFormatter.localizedString(byJoining: scheduledDays)
            return "\(name) is scheduled for \(schedule). The selected date is a \(selectedDay), so attendance cannot be recorded for that lesson."
        }
        return nil
    }

    static func timestamp(for selectedDate: Date, recordedAt: Date = Date()) -> String {
        let operationTimestamp = ISO8601DateFormatter().string(from: recordedAt)
        return selectedDate.isoDateKey + operationTimestamp.dropFirst(10)
    }

    static func containsRecord(on dateKey: String, history: [JSONValue]) -> Bool {
        history.contains { value in
            guard let rawValue = value.string else { return false }
            return String(rawValue.prefix(10)) == dateKey
        }
    }
}

enum WeekdayAttendanceScope: String, CaseIterable, Identifiable {
    case selectedDate = "Selected date"
    case allSchedules = "All scheduled days"

    var id: String { rawValue }
}

struct AttendanceView: View {
    @EnvironmentObject private var state: AppState
    @State private var programme: Programme
    @State private var date = Date()
    @State private var records: [DynamicRecord] = []
    @State private var attendanceRecords: [DynamicRecord] = []
    @State private var search = ""
    @State private var loading = false
    @State private var dayFilter = "All days"
    @State private var timeslotFilter = "All timeslots"
    @State private var levelFilter = "All levels"
    @State private var weekdayScope: WeekdayAttendanceScope = .selectedDate
    @State private var weekdayDayFilter = "All scheduled days"
    @State private var selectedRecord: DynamicRecord?

    private let showsProgrammePicker: Bool

    init(
        initialProgramme: Programme = .weekend,
        showsProgrammePicker: Bool = true
    ) {
        _programme = State(initialValue: initialProgramme)
        self.showsProgrammePicker = showsProgrammePicker
    }

    private var filtered: [DynamicRecord] {
        records.filter { record in
            guard record.matches(search),
                  programme.includesStudent(
                    active: record.values["active"]?.bool
                  ),
                  record.values["removed_from_training"]?.bool != true else {
                return false
            }

            switch programme {
            case .weekend:
                let matchesDay = dayFilter == "All days"
                    || record.values.text("student_day") == dayFilter
                let matchesTimeslot = timeslotFilter == "All timeslots"
                    || record.values.text("student_timeslot") == timeslotFilter
                let matchesLevel = levelFilter == "All levels"
                    || record.values.text("student_levelofplay") == levelFilter
                return matchesDay && matchesTimeslot && matchesLevel
            case .weekday:
                let schedules = record.values["schedules"]?.array?
                    .compactMap(\.object) ?? []
                switch weekdayScope {
                case .selectedDate:
                    let weekday = date.formatted(.dateTime.weekday(.wide))
                    return schedules.contains { $0.text("day") == weekday }
                case .allSchedules:
                    return !schedules.isEmpty
                        && (weekdayDayFilter == "All scheduled days"
                            || schedules.contains {
                                $0.text("day") == weekdayDayFilter
                            })
                }
            case .matchplay:
                return true
            case .oneToOne:
                return record.values.text("session_date").hasPrefix(date.isoDateKey)
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                HStack {
                    if showsProgrammePicker {
                        ProgrammePicker(selection: $programme)
                    } else {
                        Label(programme.title, systemImage: programme.icon)
                            .font(.headline)
                            .foregroundStyle(Theme.colour(for: programme))
                    }
                    Spacer()
                    if (programme == .weekday && weekdayScope == .selectedDate)
                        || programme == .oneToOne {
                        DatePicker(
                            programme == .weekday ? "Lesson date" : "Date",
                            selection: $date,
                            displayedComponents: .date
                        )
                            .labelsHidden()
                            .accessibilityIdentifier("attendance-lesson-date")
                    }
                }

                AppSearchField(
                    prompt: programme == .weekend
                        ? "Search Weekend student by name"
                        : "Search students or attendance",
                    text: $search
                )
                filters
                HStack {
                    Text(attendanceCountLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(scope: "\(programme.title) attendance") {
                        await load()
                    }
                }
                if filtered.isEmpty && !loading { EmptyState(icon: "checkmark.circle", title: "No records", message: programme == .oneToOne ? "Schedule 1-1 sessions from Training first." : "No active students match this filter.") }
                ForEach(filtered) { record in
                    Button {
                        selectedRecord = record
                    } label: {
                        VStack(alignment: .leading, spacing: 8) {
                        RecordCard(record: displayRecord(record), titleKeys: programme == .oneToOne ? ["student_name", "student_id"] : ["student_name"], detailKeys: attendanceDetails, query: search, status: programme == .oneToOne ? record.values.text("attendance_status", fallback: "scheduled") : nil)
                            Label("Tap to update attendance", systemImage: "hand.tap.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.blue)
                                .padding(.horizontal, 12)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("attendance-record-\(record.id)")
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .navigationTitle("Attendance")
        .refreshable { await load() }
        .task(id: attendanceLoadKey) { await load() }
        .sheet(item: $selectedRecord) { record in
            AttendanceActionsSheet(
                record: record,
                programme: programme,
                canMakeup: canMakeup(record),
                canUndo: canUndo(record),
                canReset: (programme == .weekend || programme == .matchplay)
                    && state.role == .superuser,
                canChooseMakeupProgramme: state.role == .superuser,
                sourceTrainingType: programme.makeupTrainingType,
                sourceStudentID: record.values.text("student_id", fallback: record.id),
                history: attendanceHistory(for: record),
                onMark: { status in await mark(record, status) },
                onMarkForDate: { selectedDate in
                    await mark(record, .attended, attendanceDate: selectedDate)
                },
                onMakeup: { target in await markMakeup(record, target: target) },
                onUndo: { await undo(record) },
                onReset: { await reset(record) }
            )
        }
        .overlay { if loading { LoadingOverlay(text: "Loading attendance") } }
    }

    @ViewBuilder
    private var filters: some View {
        if programme == .weekend {
            WeekendFilterPanel(
                day: $dayFilter,
                timeslot: $timeslotFilter,
                level: $levelFilter
            )
        } else if programme == .weekday {
            VStack(alignment: .leading, spacing: 14) {
                Label("View weekday students", systemImage: "calendar.badge.clock")
                    .font(.headline)
                    .foregroundStyle(Theme.colour(for: Programme.weekday))

                Picker("Weekday attendance view", selection: $weekdayScope) {
                    ForEach(WeekdayAttendanceScope.allCases) { scope in
                        Text(scope.rawValue).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("weekday-attendance-scope")

                if weekdayScope == .selectedDate {
                    Text("Showing students scheduled for \(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).year())).")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                } else {
                    FilterChips(
                        values: ["All scheduled days"]
                            + WeekdayMonthlyPaymentCalculator.scheduledDays,
                        selection: $weekdayDayFilter
                    )
                    .accessibilityIdentifier("weekday-scheduled-day-filter")

                    Text(weekdayDayFilter == "All scheduled days"
                        ? "Showing students across every weekday schedule."
                        : "Showing students with a \(weekdayDayFilter) session.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .appCard()
        }
    }

    private var attendanceDetails: [String] {
        switch programme {
        case .oneToOne:
            ["session_date", "coach_name", "attendance_status"]
        case .weekend:
            ["student_day", "student_timeslot", "attended", "missed", "total_weeks"]
        case .weekday:
            ["scheduled_sessions"]
        case .matchplay:
            ["number_of_weeks"]
        }
    }

    private var attendanceCountLabel: String {
        let item = programme == .oneToOne ? "session" : "student"
        return "\(filtered.count) \(item)\(filtered.count == 1 ? "" : "s")"
    }

    private var attendanceLoadKey: String {
        programme == .oneToOne
            ? "\(programme.rawValue)-\(date.isoDateKey)"
            : programme.rawValue
    }

    private func load() async {
        loading = records.isEmpty; defer { loading = false }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingWeekdayAttendance"),
           programme == .weekday {
            records = [
                DynamicRecord(values: [
                    "id": .string("ui-test-weekday-student-1"),
                    "student_name": .string("Brandon Teo"),
                    "schedules": .array([
                        .object(["day": .string("Wednesday"), "duration_hours": .number(2)]),
                        .object(["day": .string("Thursday"), "duration_hours": .number(1)])
                    ]),
                    "active": .bool(true)
                ]),
                DynamicRecord(values: [
                    "id": .string("ui-test-weekday-student-2"),
                    "student_name": .string("Monday Student"),
                    "schedules": .array([
                        .object(["day": .string("Monday"), "duration_hours": .number(1)])
                    ]),
                    "active": .bool(true)
                ])
            ]
            attendanceRecords = []
            return
        }

        if ProcessInfo.processInfo.arguments.contains("-uiTestingLongAttendanceList"),
           programme == .weekend {
            records = (1...14).map { index in
                let day = index.isMultiple(of: 2) ? "Sunday" : "Saturday"
                return DynamicRecord(values: [
                    "id": .string("ui-test-long-student-\(index)"),
                    "student_id": .string("ui-test-long-student-\(index)"),
                    "student_name": .string(
                        String(format: "Long List Student %02d", index)
                    ),
                    "student_day": .string(day),
                    "student_timeslot": .string(day == "Saturday" ? "2-4pm" : "8-12pm"),
                    "student_levelofplay": .string("Intermediate"),
                    "attended": .number(0),
                    "missed": .number(0),
                    "total_weeks": .number(10),
                    "attendance_records": .array([]),
                    "active": .bool(true)
                ])
            }
            attendanceRecords = []
            return
        }

        if ProcessInfo.processInfo.arguments.contains("-uiTestingAttendanceError"),
           programme == .weekend {
            let today = Date().formatted(.dateTime.weekday(.wide))
            let trainingDay = today == "Saturday" ? "Sunday" : "Saturday"
            records = [
                DynamicRecord(values: [
                    "id": .string("ui-test-weekend-student"),
                    "student_id": .string("ui-test-weekend-student"),
                    "student_name": .string("Brendan Lau"),
                    "student_day": .string(trainingDay),
                    "student_timeslot": .string(trainingDay == "Saturday" ? "2-4pm" : "8-10am"),
                    "student_levelofplay": .string("Intermediate"),
                    "attended": .number(0),
                    "missed": .number(0),
                    "total_weeks": .number(10),
                    "attendance_records": .array([]),
                    "active": .bool(true)
                ])
            ]
            attendanceRecords = []
            return
        }
#endif
        do {
            if programme == .weekend {
                records = try await BackendClient.shared.weekendStudents(
                    path: WeekendStudentWebsiteRoute.attendance
                )
                attendanceRecords = []
                return
            }
            let table = programme == .oneToOne ? "one_to_one_sessions" : programme.studentTable
            let query: [URLQueryItem]
            if programme == .oneToOne {
                let end = Calendar.current.date(byAdding: .day, value: 1, to: date)?
                    .isoDateKey ?? date.isoDateKey
                query = [
                    .init(name: "session_date", value: "gte.\(date.isoDateKey)"),
                    .init(name: "session_date", value: "lt.\(end)"),
                    .init(name: "order", value: "session_date.desc")
                ]
            } else {
                var studentQuery = [URLQueryItem(
                    name: "order",
                    value: "student_name.asc"
                )]
                if let activeFilter = programme.activeStudentFilter {
                    studentQuery.insert(activeFilter, at: 0)
                }
                query = studentQuery
            }
            records = try await BackendClient.shared.select(
                table: table,
                query: query
            )
            if let attendanceTable = programme.attendanceTable, programme != .oneToOne {
                attendanceRecords = try await BackendClient.shared.select(
                    table: attendanceTable,
                    query: [.init(name: "order", value: "updated_at.desc")]
                )
            } else {
                attendanceRecords = []
            }
        } catch { state.show(error) }
    }

    private func displayRecord(_ record: DynamicRecord) -> DynamicRecord {
        guard programme == .weekday else { return record }

        let schedules = record.values["schedules"]?.array?
            .compactMap(\.object) ?? []
        let displayedSchedules: [JSONObject]
        if weekdayScope == .selectedDate {
            let weekday = date.formatted(.dateTime.weekday(.wide))
            displayedSchedules = schedules.filter { $0.text("day") == weekday }
        } else if weekdayDayFilter != "All scheduled days" {
            displayedSchedules = schedules.filter {
                $0.text("day") == weekdayDayFilter
            }
        } else {
            displayedSchedules = schedules
        }

        var values = record.values
        values["scheduled_sessions"] = .string(
            displayedSchedules.map { schedule in
                let hours = schedule.number(
                    "duration_hours",
                    fallback: schedule.number("duration", fallback: 1)
                )
                let duration = hours == 1
                    ? "1 hour"
                    : "\(formattedNumber(hours)) hours"
                return "\(schedule.text("day")) · \(duration)"
            }
            .joined(separator: ", ")
        )
        return DynamicRecord(values: values)
    }

    private func formattedNumber(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func canUndo(_ record: DynamicRecord) -> Bool {
        switch programme {
        case .weekend:
            return !(record.values["attendance_records"]?.array ?? []).isEmpty
        case .weekday:
            let weekday = date.formatted(.dateTime.weekday(.wide))
            return attendanceRecords.contains {
                $0.values.text("weekday_student_id") == record.id
                    && $0.values.text("day_name") == weekday
            }
        case .matchplay:
            return attendanceRecords.contains {
                $0.values.text("matchplay_student_id") == record.id
            }
        case .oneToOne:
            return record.values.text("attendance_status", fallback: "scheduled") != "scheduled"
        }
    }

    private func canMakeup(_ record: DynamicRecord) -> Bool {
        switch programme {
        case .weekend:
            record.values.number("missed") > 0
        case .oneToOne:
            record.values.text("attendance_status", fallback: "scheduled") == "missed"
        case .weekday, .matchplay:
            false
        }
    }

    private func undo(_ record: DynamicRecord) async -> String? {
        switch programme {
        case .weekend:
            return await undoWeekend(record)
        case .weekday:
            return await undoWeekday(record)
        case .matchplay:
            return await undoMatchPlay(record)
        case .oneToOne:
            if record.values.text("attendance_status") == "makeup" {
                return await undoOneToOneMakeup(record)
            } else {
                return await mark(record, .scheduled)
            }
        }
    }

    private func mark(
        _ record: DynamicRecord,
        _ status: AttendanceStatus,
        attendanceDate: Date? = nil
    ) async -> String? {
        if status == .makeup {
            return await markMakeup(record, target: nil)
        }
        let currentProgrammeDate = (programme == .weekday || programme == .oneToOne)
            ? date
            : Date()
        let effectiveDate = attendanceDate ?? currentProgrammeDate
        let dateKey = effectiveDate.isoDateKey
        let now = ISO8601DateFormatter().string(from: Date())
        let isHistoricalEntry = attendanceDate != nil
        do {
            switch programme {
            case .weekend:
                let attended = record.values.number("attended")
                let missed = record.values.number("missed")
                let totalWeeks = record.values.number("total_weeks")
                guard totalWeeks <= 0 || attended + missed < totalWeeks else {
                    throw BackendError.message("This subscription has already used all of its lessons.")
                }

                if status == .attended, isHistoricalEntry {
                    if let validationError = HistoricalAttendancePolicy.validationError(
                        studentName: record.values.text("student_name"),
                        scheduledDays: [record.values.text("student_day")].filter { !$0.isEmpty },
                        selectedDate: effectiveDate
                    ) {
                        throw BackendError.message(validationError)
                    }
                } else if status == .attended {
                    let today = effectiveDate.formatted(.dateTime.weekday(.wide))
                    let trainingDay = record.values.text("student_day")
                    if let validationError = WeekendAttendancePolicy.attendedError(
                        studentName: record.values.text("student_name"),
                        trainingDay: trainingDay,
                        today: today
                    ) {
                        throw BackendError.message(validationError)
                    }
                }

                let field = status == .attended ? "attended" : "missed"
                let next = record.values.number(field) + 1
                var history = record.values["attendance_records"]?.array ?? []
                if isHistoricalEntry,
                   HistoricalAttendancePolicy.containsRecord(on: dateKey, history: history) {
                    throw BackendError.message(
                        "Attendance has already been recorded for \(formattedAttendanceDate(effectiveDate)). Undo or review that record before adding another one."
                    )
                }
                let attendanceTimestamp = isHistoricalEntry
                    ? HistoricalAttendancePolicy.timestamp(for: effectiveDate)
                    : now
                history.append(.string(
                    status == .attended
                        ? attendanceTimestamp
                        : "\(attendanceTimestamp)|missed"
                ))
                _ = try await BackendClient.shared.update(table: "students", values: [field: .number(next), "attendance_records": .array(history), "updated_at": .string(now)], filters: [.init(name: "student_id", value: "eq.\(record.values.text("student_id"))")])
                try? await auditWeekend(record, action: status == .attended ? "mark" : "missed")
            case .weekday:
                let weekday = effectiveDate.formatted(.dateTime.weekday(.wide))
                let schedules = record.values["schedules"]?.array?.compactMap(\.object) ?? []
                if isHistoricalEntry,
                   let validationError = HistoricalAttendancePolicy.validationError(
                       studentName: record.values.text("student_name"),
                       scheduledDays: schedules.map { $0.text("day") }.filter { !$0.isEmpty },
                       selectedDate: effectiveDate
                   ) {
                    throw BackendError.message(validationError)
                }
                let schedule = schedules.first { $0.text("day") == weekday }
                guard let schedule else {
                    throw BackendError.message("This student has no \(weekday) session.")
                }
                if isHistoricalEntry,
                   attendanceRecords.contains(where: {
                       $0.values.text("weekday_student_id") == record.id
                           && String($0.values.text("attendance_date").prefix(10)) == dateKey
                   }) {
                    throw BackendError.message(
                        "Attendance has already been recorded for \(formattedAttendanceDate(effectiveDate))."
                    )
                }
                _ = try await BackendClient.shared.insert(table: "weekday_attendance", values: ["weekday_student_id": .string(record.id), "attendance_date": .string(dateKey), "day_name": .string(schedule.text("day", fallback: weekday)), "status": .string(status.rawValue), "duration_hours": .number(schedule.number("duration_hours", fallback: 1)), "updated_at": .string(now)])
            case .matchplay:
                if isHistoricalEntry,
                   Calendar.current.startOfDay(for: effectiveDate) > Calendar.current.startOfDay(for: Date()) {
                    throw BackendError.message("Attendance cannot be recorded for a future date.")
                }
                if isHistoricalEntry,
                   attendanceRecords.contains(where: {
                       $0.values.text("matchplay_student_id") == record.id
                           && String($0.values.text("attendance_date").prefix(10)) == dateKey
                   }) {
                    throw BackendError.message(
                        "Attendance has already been recorded for \(formattedAttendanceDate(effectiveDate))."
                    )
                }
                _ = try await BackendClient.shared.insert(table: "matchplay_attendance", values: ["matchplay_student_id": .string(record.id), "attendance_date": .string(dateKey), "status": .string(status.rawValue), "updated_at": .string(now)])
            case .oneToOne:
                let session = try await oneToOneSession(
                    for: record,
                    attendanceDate: attendanceDate
                )
                if isHistoricalEntry,
                   session.values.text("attendance_status", fallback: "scheduled") != "scheduled" {
                    throw BackendError.message(
                        "Attendance has already been recorded for this 1-1 session on \(formattedAttendanceDate(effectiveDate))."
                    )
                }
                _ = try await BackendClient.shared.update(
                    table: "one_to_one_sessions",
                    values: [
                        "attendance_status": .string(status.rawValue),
                        "attendance_updated_at": status == .scheduled ? .null : .string(now),
                        "makeup_target_type": .null,
                        "makeup_usage_id": .null,
                        "updated_at": .string(now)
                    ],
                    filters: [.init(name: "id", value: "eq.\(session.id)")]
                )
            }
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            switch status {
            case .attended:
                return isHistoricalEntry
                    ? "\(name) was successfully marked present for \(formattedAttendanceDate(effectiveDate))."
                    : "\(name) was successfully marked present."
            case .missed:
                return "\(name) was successfully marked missed."
            case .scheduled:
                return "\(name)'s latest attendance action was successfully undone."
            case .makeup:
                return "\(name) was successfully marked for makeup."
            }
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func oneToOneSession(
        for record: DynamicRecord,
        attendanceDate: Date?
    ) async throws -> DynamicRecord {
        guard let attendanceDate else { return record }
        guard Calendar.current.startOfDay(for: attendanceDate)
                <= Calendar.current.startOfDay(for: Date()) else {
            throw BackendError.message("Attendance cannot be recorded for a future date.")
        }

        let studentID = record.values.text("student_id")
        guard !studentID.isEmpty else {
            throw BackendError.message("This 1-1 session does not have a student assigned.")
        }
        let start = attendanceDate.isoDateKey
        let end = Calendar.current.date(byAdding: .day, value: 1, to: attendanceDate)?
            .isoDateKey ?? start
        let sessions = try await BackendClient.shared.select(
            table: "one_to_one_sessions",
            query: [
                .init(name: "student_id", value: "eq.\(studentID)"),
                .init(name: "session_date", value: "gte.\(start)"),
                .init(name: "session_date", value: "lt.\(end)"),
                .init(name: "order", value: "session_date.asc"),
                .init(name: "limit", value: "10")
            ]
        )
        guard let session = sessions.first(where: {
            !$0.values.flag("removed_from_training")
        }) else {
            throw BackendError.message(
                "No 1-1 session is scheduled for \(record.values.text("student_name", fallback: "this student")) on \(formattedAttendanceDate(attendanceDate)). Add the student-coach pairing to that date before recording attendance."
            )
        }
        return session
    }

    private func formattedAttendanceDate(_ value: Date) -> String {
        value.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    /// Mirrors the website's makeup-credit workflow. Weekend users consume
    /// the latest Weekend credit against the selected student. A 1-1 missed
    /// session consumes the latest 1-1 credit and links that usage to the
    /// session so Undo can restore the credit safely.
    private func markMakeup(
        _ record: DynamicRecord,
        target: MakeupTargetSelection?
    ) async -> String? {
        let sourceType: String
        let sourceStudentID: String
        let targetDate: String
        let targetLabel: String

        switch programme {
        case .weekend:
            guard record.values.number("missed") > 0 else {
                state.show("Mark a lesson as missed before using a makeup credit.", kind: .error)
                return nil
            }
            sourceType = "weekend"
            sourceStudentID = record.values.text("student_id")
            targetDate = Date().isoDateKey
            targetLabel = "Weekend makeup lesson"
        case .oneToOne:
            guard record.values.text("attendance_status") == "missed" else {
                state.show("Mark this 1-1 session as missed before using a makeup credit.", kind: .error)
                return nil
            }
            sourceType = "one_to_one"
            sourceStudentID = record.values.text("student_id")
            targetDate = String(record.values.text("session_date").prefix(10))
            targetLabel = "1-1 makeup lesson"
        case .weekday, .matchplay:
            state.show("Use this programme's website workflow to assign a cross-programme makeup.", kind: .info)
            return nil
        }

        let resolvedTarget = target ?? MakeupTargetSelection.defaultTarget(
            forSourceType: sourceType,
            date: targetDate
        )

        do {
            let creditResponse = try await BackendClient.shared.rpc(
                "find_latest_makeup_credit",
                params: [
                    "input_source_type": .string(sourceType),
                    "input_source_student_id": .string(sourceStudentID)
                ]
            )
            guard let credit = firstObject(in: creditResponse),
                  !credit.text("id").isEmpty else {
                throw BackendError.message("No available makeup credit was found. Mark the lesson as missed first.")
            }

            let completed = try await BackendClient.shared.rpc(
                "complete_cross_programme_makeup",
                params: [
                    "input_credit_id": .string(credit.text("id")),
                    "input_target_type": .string(resolvedTarget.programme.rawValue),
                    "input_target_date": .string(resolvedTarget.dateKey),
                    "input_target_label": .string(
                        resolvedTarget.label.isEmpty ? targetLabel : resolvedTarget.label
                    ),
                    "input_target_value": .number(resolvedTarget.targetValue)
                ]
            )
            guard let usage = firstObject(in: completed),
                  !usage.text("usage_id").isEmpty else {
                throw BackendError.message("The makeup credit could not be completed.")
            }

            do {
                if programme == .weekend {
                    _ = try await BackendClient.shared.rpc(
                        "apply_weekend_makeup_usage",
                        params: [
                            "input_student_id": .string(sourceStudentID),
                            "input_usage_id": .string(usage.text("usage_id"))
                        ]
                    )
                    try? await auditWeekend(record, action: "makeup")
                } else {
                    let now = ISO8601DateFormatter().string(from: Date())
                    _ = try await BackendClient.shared.update(
                        table: "one_to_one_sessions",
                        values: [
                            "attendance_status": .string("makeup"),
                            "attendance_updated_at": .string(now),
                            "makeup_target_type": .string(resolvedTarget.programme.rawValue),
                            "makeup_usage_id": .string(usage.text("usage_id")),
                            "updated_at": .string(now)
                        ],
                        filters: [.init(name: "id", value: "eq.\(record.id)")]
                    )
                }
            } catch {
                _ = try? await BackendClient.shared.rpc(
                    "undo_cross_programme_makeup",
                    params: ["input_usage_id": .string(usage.text("usage_id"))]
                )
                throw error
            }

            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name) was successfully marked for a \(resolvedTarget.programme.title) makeup."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func undoOneToOneMakeup(_ record: DynamicRecord) async -> String? {
        do {
            _ = try await BackendClient.shared.rpc(
                "undo_one_to_one_makeup_status",
                params: ["input_session_id": .string(record.id)]
            )
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s makeup was successfully undone and returned to missed."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func firstObject(in value: JSONValue) -> JSONObject? {
        value.object ?? value.array?.first?.object
    }

    private func undoWeekend(_ record: DynamicRecord) async -> String? {
        var history = record.values["attendance_records"]?.array ?? []
        guard let lastValue = history.last?.string else {
            state.show("There is no attendance action to undo.", kind: .info)
            return nil
        }

        let parts = lastValue.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        let status = parts.count > 1 ? parts[1] : "mark"
        var attended = record.values.number("attended")
        var missed = record.values.number("missed")

        do {
            if status == "makeup" {
                if parts.count > 4, !parts[4].isEmpty {
                    _ = try await BackendClient.shared.rpc(
                        "undo_cross_programme_makeup",
                        params: ["input_usage_id": .string(parts[4])]
                    )
                }
                attended = max(0, attended - 1)
                missed += 1
                let missedDate = parts.count > 2 && !parts[2].isEmpty ? parts[2] : parts[0]
                history[history.count - 1] = .string("\(missedDate)|missed")
            } else if status == "missed" {
                _ = try await BackendClient.shared.rpc(
                    "cancel_weekend_missed_credit",
                    params: [
                        "input_student_id": .string(record.values.text("student_id")),
                        "input_missed_date": .string(parts[0])
                    ]
                )
                missed = max(0, missed - 1)
                history.removeLast()
            } else {
                attended = max(0, attended - 1)
                history.removeLast()
            }

            _ = try await BackendClient.shared.update(
                table: "students",
                values: [
                    "attended": .number(attended),
                    "missed": .number(missed),
                    "attendance_records": .array(history),
                    "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                ],
                filters: [.init(name: "student_id", value: "eq.\(record.values.text("student_id"))")]
            )
            try? await auditWeekend(record, action: "undo")
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s latest attendance action was successfully undone."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func resetWeekend(_ record: DynamicRecord) async -> String? {
        do {
            _ = try await BackendClient.shared.rpc(
                "reset_weekend_course_and_makeup",
                params: ["input_student_id": .string(record.values.text("student_id"))]
            )
            try? await auditWeekend(record, action: "reset")
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s Weekend course was successfully reset."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func reset(_ record: DynamicRecord) async -> String? {
        guard state.role == .superuser else {
            state.show("Only superusers can reset a course.", kind: .error)
            return nil
        }
        if programme == .matchplay {
            return await resetMatchPlay(record)
        } else {
            return await resetWeekend(record)
        }
    }

    private func resetMatchPlay(_ record: DynamicRecord) async -> String? {
        let studentAttendance = attendanceRecords.filter {
            $0.values.text("matchplay_student_id") == record.id
        }
        do {
            for attendance in studentAttendance where attendance.values.text("status") == "makeup" {
                let usageID = attendance.values.text("makeup_usage_id")
                if !usageID.isEmpty {
                    _ = try await BackendClient.shared.rpc(
                        "undo_cross_programme_makeup",
                        params: ["input_usage_id": .string(usageID)]
                    )
                }
            }
            try await BackendClient.shared.delete(
                table: "matchplay_attendance",
                filters: [.init(name: "matchplay_student_id", value: "eq.\(record.id)")]
            )
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s MatchPlay attendance was successfully reset."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func undoWeekday(_ record: DynamicRecord) async -> String? {
        let weekday = date.formatted(.dateTime.weekday(.wide))
        guard let latest = attendanceRecords.first(where: {
            $0.values.text("weekday_student_id") == record.id
                && $0.values.text("day_name") == weekday
        }) else {
            state.show("There is no \(weekday) action to undo.", kind: .info)
            return nil
        }
        do {
            _ = try await BackendClient.shared.rpc(
                "undo_weekday_attendance_action",
                params: ["input_attendance_id": .string(latest.id)]
            )
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s latest Weekday attendance action was successfully undone."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func undoMatchPlay(_ record: DynamicRecord) async -> String? {
        guard let latest = attendanceRecords.first(where: {
            $0.values.text("matchplay_student_id") == record.id
        }) else {
            state.show("There is no MatchPlay action to undo.", kind: .info)
            return nil
        }
        do {
            if latest.values.text("status") == "makeup" {
                _ = try await BackendClient.shared.rpc(
                    "undo_matchplay_makeup_status",
                    params: ["input_attendance_id": .string(latest.id)]
                )
            } else {
                try await BackendClient.shared.delete(
                    table: "matchplay_attendance",
                    filters: [.init(name: "id", value: "eq.\(latest.id)")]
                )
            }
            await load()
            let name = record.values.text("student_name", fallback: "Student")
            return "\(name)'s latest MatchPlay attendance action was successfully undone."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func attendanceHistory(for record: DynamicRecord) -> [AttendanceHistoryEntry] {
        switch programme {
        case .weekend:
            let values = record.values["attendance_records"]?.array ?? []
            return Array(values.enumerated()).reversed().compactMap { index, value in
                guard let rawValue = value.string else { return nil }
                let parts = rawValue
                    .split(separator: "|", omittingEmptySubsequences: false)
                    .map(String.init)
                let rawStatus = parts.count > 1 ? parts[1].lowercased() : "attended"
                let status: String
                switch rawStatus {
                case "mark", "attended", "present": status = "Attended"
                case "missed": status = "Missed"
                case "makeup": status = "Makeup"
                default: status = rawStatus.capitalized
                }

                let detail: String?
                if rawStatus == "makeup", parts.count > 3, !parts[3].isEmpty {
                    detail = "Makeup programme: \(parts[3].replacingOccurrences(of: "_", with: " ").capitalized)"
                } else {
                    detail = nil
                }

                return AttendanceHistoryEntry(
                    id: "weekend-\(index)-\(rawValue)",
                    status: status,
                    date: readableAttendanceDate(parts.first ?? rawValue),
                    detail: detail
                )
            }

        case .weekday:
            return attendanceRecords.compactMap { attendance in
                guard attendance.values.text("weekday_student_id") == record.id else {
                    return nil
                }
                let day = attendance.values.text("day_name")
                return AttendanceHistoryEntry(
                    id: "weekday-\(attendance.id)",
                    status: attendance.values.text("status", fallback: "Recorded").capitalized,
                    date: readableAttendanceDate(attendance.values.text("attendance_date")),
                    detail: day.isEmpty ? nil : day
                )
            }

        case .matchplay:
            return attendanceRecords.compactMap { attendance in
                guard attendance.values.text("matchplay_student_id") == record.id else {
                    return nil
                }
                return AttendanceHistoryEntry(
                    id: "matchplay-\(attendance.id)",
                    status: attendance.values.text("status", fallback: "Recorded").capitalized,
                    date: readableAttendanceDate(attendance.values.text("attendance_date")),
                    detail: nil
                )
            }

        case .oneToOne:
            let studentID = record.values.text("student_id")
            return records.compactMap { session in
                let status = session.values.text("attendance_status", fallback: "scheduled")
                guard session.values.text("student_id") == studentID,
                      status != "scheduled",
                      !session.values.flag("removed_from_training") else {
                    return nil
                }
                let coach = session.values.text("coach_name")
                return AttendanceHistoryEntry(
                    id: "one-to-one-\(session.id)",
                    status: status.capitalized,
                    date: readableAttendanceDate(session.values.text("session_date")),
                    detail: coach.isEmpty ? nil : "Coach: \(coach)"
                )
            }
        }
    }

    private func readableAttendanceDate(_ rawValue: String) -> String {
        let dateKey = String(rawValue.prefix(10))
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        guard let parsed = parser.date(from: dateKey) else {
            return rawValue.isEmpty ? "Date unavailable" : rawValue
        }
        return parsed.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func auditWeekend(_ record: DynamicRecord, action: String) async throws {
        _ = try await BackendClient.shared.websiteJSON(
            path: "/api/audit/log-attendance",
            method: "POST",
            body: [
                "student_id": .string(record.values.text("student_id")),
                "action": .string(action)
            ]
        )
    }
}

extension Programme {
    var makeupTrainingType: String {
        switch self {
        case .weekend: "weekend"
        case .weekday: "weekday"
        case .matchplay: "matchplay"
        case .oneToOne: "one_to_one"
        }
    }
}

enum MakeupTargetProgramme: String, CaseIterable, Identifiable {
    case weekend
    case weekday
    case oneToOne = "one_to_one"
    case matchplay

    var id: String { rawValue }

    var title: String {
        switch self {
        case .weekend: "Weekend"
        case .weekday: "Weekday"
        case .oneToOne: "1-1"
        case .matchplay: "MatchPlay"
        }
    }

    var icon: String {
        switch self {
        case .weekend: "calendar"
        case .weekday: "calendar.badge.clock"
        case .oneToOne: "person.2.fill"
        case .matchplay: "figure.badminton"
        }
    }

    var colour: Color {
        switch self {
        case .weekend: Theme.blue
        case .weekday: .indigo
        case .oneToOne: Theme.green
        case .matchplay: Theme.purple
        }
    }

    var defaultTargetValue: Double {
        switch self {
        case .weekend: 40
        case .weekday, .oneToOne, .matchplay: 80
        }
    }

    var defaultLabel: String {
        switch self {
        case .weekend: "Weekend makeup lesson"
        case .weekday: "Weekday 1h makeup lesson"
        case .oneToOne: "1-1 makeup lesson"
        case .matchplay: "MatchPlay makeup lesson"
        }
    }

    static func from(trainingType: String) -> MakeupTargetProgramme {
        MakeupTargetProgramme(rawValue: trainingType) ?? .weekend
    }
}

struct MakeupTargetSelection {
    let programme: MakeupTargetProgramme
    let dateKey: String
    let label: String
    let targetValue: Double

    static func defaultTarget(
        forSourceType sourceType: String,
        date: String
    ) -> MakeupTargetSelection {
        let programme = MakeupTargetProgramme.from(trainingType: sourceType)
        return MakeupTargetSelection(
            programme: programme,
            dateKey: String(date.prefix(10)),
            label: programme.defaultLabel,
            targetValue: programme.defaultTargetValue
        )
    }
}

private struct AttendanceHistoryEntry: Identifiable {
    let id: String
    let status: String
    let date: String
    let detail: String?

    var icon: String {
        switch status.lowercased() {
        case "attended", "present": "checkmark.circle.fill"
        case "missed": "xmark.circle.fill"
        case "makeup": "arrow.triangle.2.circlepath.circle.fill"
        default: "clock.fill"
        }
    }

    var color: Color {
        switch status.lowercased() {
        case "attended", "present": Theme.green
        case "missed": Theme.red
        case "makeup": Theme.blue
        default: Theme.secondaryText
        }
    }
}

struct MakeupProgrammeChooser: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    let studentName: String
    let sourceTrainingType: String
    let sourceStudentID: String
    let onConfirm: (MakeupTargetSelection) async -> String?
    let onFinished: () -> Void

    @State private var selectedProgramme = MakeupTargetProgramme.weekend
    @State private var targetDate = Date()
    @State private var targetLabel = MakeupTargetProgramme.weekend.defaultLabel
    @State private var targetValue = MakeupTargetProgramme.weekend.defaultTargetValue
    @State private var weekdayHours = 1
    @State private var credit: JSONObject?
    @State private var loadingCredit = false
    @State private var operationMessage: String?
    @State private var successMessage: String?
    @State private var errorMessage: String?

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Choose Makeup Programme",
                    cancelDisabled: operationMessage != nil,
                    onCancel: { dismiss() }
                )
                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(studentName)
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text("Choose where this makeup credit will be used.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .appCard()

                        SectionHeading(
                            title: "Programme",
                            subtitle: "The credit can be used for Weekend, Weekday, 1-1 or MatchPlay."
                        )

                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(MakeupTargetProgramme.allCases) { programme in
                                Button {
                                    selectedProgramme = programme
                                } label: {
                                    VStack(spacing: 10) {
                                        Image(systemName: programme.icon)
                                            .font(.title3.weight(.semibold))
                                        Text(programme.title)
                                            .font(.subheadline.weight(.semibold))
                                    }
                                    .foregroundStyle(
                                        selectedProgramme == programme ? .white : programme.colour
                                    )
                                    .frame(maxWidth: .infinity, minHeight: 86)
                                    .background(
                                        selectedProgramme == programme
                                            ? programme.colour
                                            : programme.colour.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .stroke(
                                                selectedProgramme == programme
                                                    ? programme.colour
                                                    : Theme.border,
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Choose \(programme.title) makeup")
                            }
                        }

                        VStack(spacing: 0) {
                            DatePicker(
                                "Makeup date",
                                selection: $targetDate,
                                displayedComponents: .date
                            )
                            .padding(.vertical, 12)

                            Divider()

                            if selectedProgramme == .weekday {
                                Stepper(value: $weekdayHours, in: 1...3) {
                                    LabeledContent("Lesson duration", value: "\(weekdayHours) hour\(weekdayHours == 1 ? "" : "s")")
                                }
                                .padding(.vertical, 12)

                                Divider()
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Makeup description")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.secondaryText)
                                TextField("e.g. Weekend makeup lesson", text: $targetLabel)
                                    .textFieldStyle(.plain)
                            }
                            .padding(.vertical, 12)

                            Divider()

                            TextField(
                                "Lesson value",
                                value: $targetValue,
                                format: .currency(code: "SGD")
                            )
                            .keyboardType(.decimalPad)
                            .padding(.vertical, 12)
                        }
                        .padding(.horizontal, 16)
                        .appCard(padding: 0)

                        creditSummary

                        if let errorMessage {
                            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                                .font(.subheadline)
                                .foregroundStyle(Theme.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .appCard()
                        }

                        AsyncActionButton(
                            title: "Confirm \(selectedProgramme.title) Makeup",
                            progressTitle: "Recording makeup…",
                            icon: "checkmark.circle.fill",
                            disabled: credit == nil || loadingCredit || targetLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ) {
                            await confirm()
                        }
                        .tint(selectedProgramme.colour)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Theme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(operationMessage != nil)
        .task { await loadCredit() }
        .onChange(of: selectedProgramme) { _, programme in
            targetLabel = programme.defaultLabel
            targetValue = programme.defaultTargetValue
            if programme == .weekday { weekdayHours = 1 }
        }
        .onChange(of: weekdayHours) { _, hours in
            guard selectedProgramme == .weekday else { return }
            targetLabel = "Weekday \(hours)h makeup lesson"
            targetValue = Double(hours) * 80
        }
        .alert("Makeup Recorded", isPresented: Binding(
            get: { successMessage != nil },
            set: { if !$0 { successMessage = nil } }
        )) {
            Button("Done") {
                dismiss()
                onFinished()
            }
        } message: {
            Text(successMessage ?? "The makeup was recorded successfully.")
        }
        .overlay {
            if let operationMessage {
                LoadingOverlay(text: operationMessage)
            } else if loadingCredit {
                LoadingOverlay(text: "Checking available makeup credit")
            }
        }
    }

    @ViewBuilder
    private var creditSummary: some View {
        if let credit {
            let value = credit.number("credit_value")
            let topUp = max(0, targetValue - value)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Available credit", systemImage: "ticket.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text(value, format: .currency(code: "SGD"))
                        .font(.headline)
                        .foregroundStyle(Theme.green)
                }

                if topUp > 0 {
                    Divider()
                    LabeledContent("Estimated top-up") {
                        Text(topUp, format: .currency(code: "SGD"))
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.amber)
                    }
                } else {
                    Label("No top-up is expected.", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.green)
                }
            }
            .appCard()
        }
    }

    private func loadCredit() async {
        loadingCredit = true
        errorMessage = nil
        defer { loadingCredit = false }
        do {
            let response = try await BackendClient.shared.rpc(
                "find_latest_makeup_credit",
                params: [
                    "input_source_type": .string(sourceTrainingType),
                    "input_source_student_id": .string(sourceStudentID)
                ]
            )
            guard let availableCredit = response.object ?? response.array?.first?.object,
                  !availableCredit.text("id").isEmpty else {
                credit = nil
                errorMessage = "No available makeup credit was found. Mark the lesson as missed first."
                return
            }
            credit = availableCredit
        } catch {
            credit = nil
            errorMessage = error.localizedDescription
        }
    }

    private func confirm() async {
        operationMessage = "Recording \(selectedProgramme.title) makeup"
        errorMessage = nil
        let previousNoticeID = state.notice?.id
        let selection = MakeupTargetSelection(
            programme: selectedProgramme,
            dateKey: targetDate.isoDateKey,
            label: targetLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            targetValue: targetValue
        )
        let result = await onConfirm(selection)
        operationMessage = nil
        if let result {
            successMessage = result
        } else if let notice = state.notice, notice.id != previousNoticeID {
            errorMessage = notice.text
            state.notice = nil
        } else {
            errorMessage = "The makeup could not be recorded. Please check the details and try again."
        }
    }
}

private struct AttendanceActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    let record: DynamicRecord
    let programme: Programme
    let canMakeup: Bool
    let canUndo: Bool
    let canReset: Bool
    let canChooseMakeupProgramme: Bool
    let sourceTrainingType: String
    let sourceStudentID: String
    let history: [AttendanceHistoryEntry]
    let onMark: (AttendanceStatus) async -> String?
    let onMarkForDate: (Date) async -> String?
    let onMakeup: (MakeupTargetSelection?) async -> String?
    let onUndo: () async -> String?
    let onReset: () async -> String?

    @State private var operationMessage: String?
    @State private var actionFeedback: AttendanceActionFeedback?
    @State private var showMakeupProgrammeChooser = false
    @State private var showHistoricalAttendance = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ZStack {
                    Text("Update Attendance")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    HStack {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.blue)
                            .disabled(operationMessage != nil)
                        Spacer()
                    }
                }
                .frame(minHeight: 56)
                .padding(.horizontal, 20)
                .background(Color(uiColor: .systemGroupedBackground))

                Divider()

                Form {
                Section("Student") {
                    LabeledContent("Name", value: record.values.text("student_name", fallback: "Student"))
                    if programme == .weekend {
                        LabeledContent("Session") {
                            Text([record.values.text("student_day"), record.values.text("student_timeslot")]
                                .filter { !$0.isEmpty }
                                .joined(separator: " • "))
                        }
                        LabeledContent("Progress") {
                            Text("\(Int(record.values.number("attended"))) attended • \(Int(record.values.number("missed"))) missed")
                        }
                    }
                }

                Section {
                    if history.isEmpty {
                        ContentUnavailableView(
                            "No attendance recorded",
                            systemImage: "calendar.badge.clock",
                            description: Text("This student's attended, missed and makeup sessions will appear here.")
                        )
                    } else {
                        ForEach(history.prefix(20)) { entry in
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: entry.icon)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(entry.color)
                                    .frame(width: 24, height: 24)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.status)
                                        .font(.body.weight(.semibold))
                                    Text(entry.date)
                                        .font(.caption)
                                        .foregroundStyle(Theme.secondaryText)
                                    if let detail = entry.detail, !detail.isEmpty {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                }

                                Spacer(minLength: 8)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } header: {
                    Text("Recent Attendance")
                } footer: {
                    if history.count > 20 {
                        Text("Showing the 20 most recent of \(history.count) recorded sessions.")
                    }
                }

                Section("Attendance action") {
                    AsyncActionButton(
                        title: "Mark Attended",
                        progressTitle: "Updating attendance…",
                        icon: "checkmark.circle.fill"
                    ) {
                        await perform("Updating attendance status") {
                            await onMark(.attended)
                        }
                    }
                    .tint(Theme.green)

                    Button {
                        showHistoricalAttendance = true
                    } label: {
                        Label("Mark Attended for Another Date", systemImage: "calendar.badge.checkmark")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle())
                    .tint(Theme.green)
                    .disabled(operationMessage != nil)
                    .touchTarget()
                    .accessibilityIdentifier("mark-attended-another-date")

                    AsyncActionButton(
                        title: "Mark Missed",
                        progressTitle: "Updating attendance…",
                        icon: "xmark.circle.fill"
                    ) {
                        await perform("Updating attendance status") {
                            await onMark(.missed)
                        }
                    }
                    .tint(Theme.red)

                    AsyncActionButton(
                        title: "Mark Makeup",
                        progressTitle: "Applying makeup credit…",
                        icon: "arrow.triangle.2.circlepath"
                    ) {
                        guard canMakeup else {
                            let message = programme == .oneToOne
                                ? "Mark this 1-1 session as missed before using a makeup credit."
                                : "Mark a lesson as missed before using a makeup credit."
                            actionFeedback = AttendanceActionFeedback(
                                kind: .failure,
                                message: message
                            )
                            return
                        }

                        if canChooseMakeupProgramme {
                            showMakeupProgrammeChooser = true
                        } else {
                            await perform("Applying makeup credit") {
                                await onMakeup(nil)
                            }
                        }
                    }
                    .tint(Theme.blue)

                    if canUndo {
                        AsyncActionButton(
                            title: "Undo Latest Action",
                            progressTitle: "Undoing attendance…",
                            icon: "arrow.uturn.backward"
                        ) {
                            await perform("Undoing latest attendance action") {
                                await onUndo()
                            }
                        }
                        .tint(Theme.amber)
                    }
                }

                if canReset {
                    Section {
                        AsyncActionButton(
                            title: "Reset Course",
                            progressTitle: "Resetting course…",
                            icon: "arrow.counterclockwise",
                            role: .destructive
                        ) {
                            await perform("Resetting course attendance") {
                                await onReset()
                            }
                        }
                        .tint(Theme.red)
                    } footer: {
                        Text("This resets the course and reconciles its makeup records.")
                    }
                }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .alert(item: $actionFeedback) { feedback in
                switch feedback.kind {
                case .success:
                    Alert(
                        title: Text("Attendance Updated"),
                        message: Text(feedback.message),
                        dismissButton: .default(Text("Done")) { dismiss() }
                    )
                case .failure:
                    Alert(
                        title: Text("Unable to Update Attendance"),
                        message: Text(feedback.message),
                        dismissButton: .default(Text("OK"))
                    )
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(operationMessage != nil)
        .sheet(isPresented: $showMakeupProgrammeChooser) {
            MakeupProgrammeChooser(
                studentName: record.values.text("student_name", fallback: "Student"),
                sourceTrainingType: sourceTrainingType,
                sourceStudentID: sourceStudentID,
                onConfirm: { selection in
                    await onMakeup(selection)
                },
                onFinished: { dismiss() }
            )
        }
        .sheet(isPresented: $showHistoricalAttendance) {
            HistoricalAttendanceSheet(
                studentName: record.values.text("student_name", fallback: "Student"),
                programme: programme,
                scheduledDescription: scheduledDescription,
                initialDate: suggestedHistoricalDate,
                onConfirm: onMarkForDate,
                onFinished: { dismiss() }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .overlay {
            if let operationMessage {
                LoadingOverlay(text: operationMessage)
            }
        }
    }

    private func perform(
        _ message: String,
        operation: () async -> String?
    ) async {
        operationMessage = message
        let previousNoticeID = state.notice?.id
        let result = await operation()
        operationMessage = nil

        if let result {
            actionFeedback = AttendanceActionFeedback(kind: .success, message: result)
        } else if let notice = state.notice, notice.id != previousNoticeID {
            actionFeedback = AttendanceActionFeedback(kind: .failure, message: notice.text)
            // The sheet now owns this message. Clear the app-level notice so
            // the same failure is not shown again after the sheet is closed.
            state.notice = nil
        } else {
            actionFeedback = AttendanceActionFeedback(
                kind: .failure,
                message: "The action could not be completed. Please try again."
            )
        }
    }

    private var scheduledDescription: String? {
        switch programme {
        case .weekend:
            let session = [
                record.values.text("student_day"),
                record.values.text("student_timeslot")
            ]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
            return session.isEmpty ? nil : session
        case .weekday:
            let days = record.values["schedules"]?.array?
                .compactMap(\.object)
                .map { $0.text("day") }
                .filter { !$0.isEmpty } ?? []
            return days.isEmpty ? nil : "Scheduled: \(ListFormatter.localizedString(byJoining: days))"
        case .matchplay:
            return "Choose the date of the MatchPlay lesson."
        case .oneToOne:
            return "The selected date must already have a student-coach pairing."
        }
    }

    private var suggestedHistoricalDate: Date {
        if programme == .oneToOne {
            let dateKey = String(record.values.text("session_date").prefix(10))
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.calendar = Calendar(identifier: .gregorian)
            parser.dateFormat = "yyyy-MM-dd"
            if let sessionDate = parser.date(from: dateKey), sessionDate <= Date() {
                return sessionDate
            }
        }

        let scheduledDays: [String]
        switch programme {
        case .weekend:
            scheduledDays = [record.values.text("student_day")].filter { !$0.isEmpty }
        case .weekday:
            scheduledDays = record.values["schedules"]?.array?
                .compactMap(\.object)
                .map { $0.text("day") }
                .filter { !$0.isEmpty } ?? []
        case .matchplay, .oneToOne:
            scheduledDays = []
        }

        for offset in 1...7 {
            guard let candidate = Calendar.current.date(
                byAdding: .day,
                value: -offset,
                to: Date()
            ) else { continue }
            if scheduledDays.isEmpty
                || scheduledDays.contains(candidate.formatted(.dateTime.weekday(.wide))) {
                return candidate
            }
        }
        return Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date()
    }
}

private struct HistoricalAttendanceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    let studentName: String
    let programme: Programme
    let scheduledDescription: String?
    let onConfirm: (Date) async -> String?
    let onFinished: () -> Void

    @State private var selectedDate: Date
    @State private var operationMessage: String?
    @State private var feedback: AttendanceActionFeedback?

    init(
        studentName: String,
        programme: Programme,
        scheduledDescription: String?,
        initialDate: Date,
        onConfirm: @escaping (Date) async -> String?,
        onFinished: @escaping () -> Void
    ) {
        self.studentName = studentName
        self.programme = programme
        self.scheduledDescription = scheduledDescription
        self.onConfirm = onConfirm
        self.onFinished = onFinished
        _selectedDate = State(initialValue: initialDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            PlainSheetHeader(
                title: "Mark Another Date",
                onCancel: { if operationMessage == nil { dismiss() } }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Historical attendance", systemImage: "calendar.badge.checkmark")
                            .font(.headline)
                            .foregroundStyle(Theme.colour(for: programme))
                        Text("Choose the actual lesson date that \(studentName) attended.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondaryText)
                        if let scheduledDescription, !scheduledDescription.isEmpty {
                            Text(scheduledDescription)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }

                    DatePicker(
                        "Lesson date",
                        selection: $selectedDate,
                        in: ...Date(),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.graphical)
                    .accessibilityIdentifier("historical-attendance-date-picker")

                    VStack(alignment: .leading, spacing: 5) {
                        Text("Attendance will be recorded for")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                        Text(selectedDate.formatted(
                            .dateTime.weekday(.wide).day().month(.wide).year()
                        ))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                    }
                    .appCard()

                    AsyncActionButton(
                        title: "Mark Attended for This Date",
                        progressTitle: "Recording historical attendance…",
                        icon: "checkmark.circle.fill"
                    ) {
                        await submit()
                    }
                    .tint(Theme.green)
                    .accessibilityIdentifier("confirm-historical-attendance")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 20)
            }
        }
        .background(Theme.background)
        .interactiveDismissDisabled(operationMessage != nil)
        .overlay {
            if let operationMessage { LoadingOverlay(text: operationMessage) }
        }
        .alert(item: $feedback) { feedback in
            switch feedback.kind {
            case .success:
                Alert(
                    title: Text("Attendance Updated"),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("Done")) {
                        dismiss()
                        onFinished()
                    }
                )
            case .failure:
                Alert(
                    title: Text("Unable to Update Attendance"),
                    message: Text(feedback.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private func submit() async {
        operationMessage = "Recording attendance for \(selectedDate.formatted(.dateTime.day().month(.abbreviated)))"
        let previousNoticeID = state.notice?.id
        let result = await onConfirm(selectedDate)
        operationMessage = nil

        if let result {
            feedback = AttendanceActionFeedback(kind: .success, message: result)
        } else if let notice = state.notice, notice.id != previousNoticeID {
            feedback = AttendanceActionFeedback(kind: .failure, message: notice.text)
            state.notice = nil
        } else {
            feedback = AttendanceActionFeedback(
                kind: .failure,
                message: "The historical attendance could not be recorded. Please try again."
            )
        }
    }
}

private struct AttendanceActionFeedback: Identifiable {
    enum Kind {
        case success
        case failure
    }

    let id = UUID()
    let kind: Kind
    let message: String
}
