import SwiftUI

struct TrainingView: View {
    @EnvironmentObject private var state: AppState

    @State private var month = Date()
    @State private var sessions: [DynamicRecord] = []
    @State private var students: [DynamicRecord] = []
    @State private var coaches: [DynamicRecord] = []
    @State private var selectedStudent: [String: String] = [:]
    @State private var selectedCoach: [String: String] = [:]
    @State private var pendingRemoval: DynamicRecord?
    @State private var pendingAttendanceAction: TrainingAttendanceAction?
    @State private var pendingMakeupSession: DynamicRecord?
    @State private var attendanceSuccessMessage: String?
    @State private var loading = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                monthSelector
                    .padding(.bottom, 12)

                HStack {
                    Text("\(monthlyPairCount) scheduled pair\(monthlyPairCount == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(
                        scope: "\(month.formatted(.dateTime.month(.wide).year())) 1-1 schedule"
                    ) {
                        await load()
                    }
                }
                .padding(.bottom, 6)

                ForEach(sundaysInMonth, id: \.isoDateKey) { sunday in
                    weekSection(sunday)
                    Divider()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("1-1 Training")
        .task(id: month.monthKey) { await load() }
        .refreshable { await load() }
        .alert("Remove this pair from the schedule?", isPresented: Binding(
            get: { pendingRemoval != nil },
            set: { if !$0 { pendingRemoval = nil } }
        )) {
            Button("Remove", role: .destructive) {
                if let session = pendingRemoval {
                    Task { await remove(session) }
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("The payment record is retained, matching the website workflow.")
        }
        .alert("Update 1-1 attendance?", isPresented: Binding(
            get: { pendingAttendanceAction != nil },
            set: { if !$0 { pendingAttendanceAction = nil } }
        )) {
            Button(pendingAttendanceAction?.buttonTitle ?? "Update") {
                guard let action = pendingAttendanceAction else { return }
                pendingAttendanceAction = nil
                Task {
                    if action.status == "makeup" {
                        attendanceSuccessMessage = await markMakeup(action.session, target: nil)
                    } else {
                        await mark(action.session, status: action.status)
                    }
                }
            }
            Button("Cancel", role: .cancel) { pendingAttendanceAction = nil }
        } message: {
            Text(pendingAttendanceAction?.message ?? "The selected session will be updated.")
        }
        .alert("Attendance Updated", isPresented: Binding(
            get: { attendanceSuccessMessage != nil },
            set: { if !$0 { attendanceSuccessMessage = nil } }
        )) {
            Button("Done") { attendanceSuccessMessage = nil }
        } message: {
            Text(attendanceSuccessMessage ?? "Attendance was updated successfully.")
        }
        .sheet(item: $pendingMakeupSession) { session in
            MakeupProgrammeChooser(
                studentName: session.values.text("student_name", fallback: "Student"),
                sourceTrainingType: "one_to_one",
                sourceStudentID: session.values.text("student_id"),
                onConfirm: { selection in
                    await markMakeup(session, target: selection)
                },
                onFinished: { pendingMakeupSession = nil }
            )
        }
        .overlay { if loading { LoadingOverlay(text: "Loading monthly schedule") } }
    }

    private var monthSelector: some View {
        HStack {
            Button {
                changeMonth(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))

            Spacer()

            Button {
                changeMonth(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func weekSection(_ date: Date) -> some View {
        let dateKey = date.isoDateKey
        let dateSessions = sessions.filter {
            $0.values.text("session_date").hasPrefix(dateKey)
                && !$0.values.flag("removed_from_training")
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .font(.headline)
                    Text("\(dateSessions.count) pair\(dateSessions.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }

            if dateSessions.isEmpty {
                Text("No student and coach paired yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(dateSessions.enumerated()), id: \.offset) { index, session in
                        pairRow(session)
                        if index < dateSessions.count - 1 { Divider() }
                    }
                }
            }

            if state.role.permissionRank >= UserRole.admin.permissionRank {
                pairComposer(for: date)
                    .padding(.top, 2)
            }
        }
        .padding(.vertical, 16)
    }

    private func pairRow(_ session: DynamicRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                pairingRole(
                    label: "COACH",
                    value: session.values.text("coach_name", fallback: "Unassigned")
                )

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.blue)
                    .accessibilityHidden(true)

                pairingRole(
                    label: "1-1 STUDENT",
                    value: session.values.text("student_name", fallback: "Unassigned")
                )
            }

            HStack(spacing: 10) {
                StatusBadge(
                    text: session.values.text("attendance_status", fallback: "scheduled").capitalized,
                    color: statusColor(session.values.text("attendance_status", fallback: "scheduled"))
                )
                Spacer()

                if state.role != .member {
                    Menu {
                    Button("Mark Attended", systemImage: "checkmark") {
                        pendingAttendanceAction = .init(session: session, status: "attended")
                    }
                    .disabled(session.values.text("attendance_status") == "attended"
                        || session.values.text("attendance_status") == "makeup")

                    Button("Mark Missed", systemImage: "xmark") {
                        pendingAttendanceAction = .init(session: session, status: "missed")
                    }
                    .disabled(session.values.text("attendance_status") == "missed"
                        || session.values.text("attendance_status") == "makeup")

                    Button("Mark Makeup", systemImage: "arrow.triangle.2.circlepath") {
                        if state.role == .superuser {
                            pendingMakeupSession = session
                        } else {
                            pendingAttendanceAction = .init(session: session, status: "makeup")
                        }
                    }
                    .disabled(session.values.text("attendance_status", fallback: "scheduled") != "missed")

                    if session.values.text("attendance_status", fallback: "scheduled") != "scheduled" {
                        Button("Undo Attendance", systemImage: "arrow.uturn.backward") {
                            pendingAttendanceAction = .init(session: session, status: "scheduled")
                        }
                    }

                    Divider()

                    Button("Remove Pair", systemImage: "trash", role: .destructive) {
                        pendingRemoval = session
                    }
                    } label: {
                        Label("Pair actions", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Pair actions for \(session.values.text("student_name", fallback: "student"))")
                }
            }
        }
        .padding(.vertical, 9)
    }

    private func pairingRole(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.body.weight(.semibold))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func pairComposer(for date: Date) -> some View {
        let dateKey = date.isoDateKey
        return VStack(alignment: .leading, spacing: 10) {
            Text("Add pair")
                .font(.subheadline.weight(.semibold))

            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("COACH")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                    Picker("Coach", selection: selectionBinding(in: $selectedCoach, key: dateKey)) {
                        Text("Choose").tag("")
                        ForEach(coaches) { coach in
                            Text(displayName(coach)).tag(coach.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("coach-picker-\(dateKey)")
                }

                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Theme.blue)
                    .padding(.top, 18)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("1-1 STUDENT")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                    Picker("1-1 Student", selection: selectionBinding(in: $selectedStudent, key: dateKey)) {
                        Text("Choose").tag("")
                        ForEach(students) { student in
                            Text(student.values.text("student_name", fallback: "Student")).tag(student.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("student-picker-\(dateKey)")
                }
            }

            AsyncActionButton(
                title: "Add Pair",
                progressTitle: "Adding pair…",
                icon: "plus",
                disabled: (selectedCoach[dateKey] ?? "").isEmpty
                    || (selectedStudent[dateKey] ?? "").isEmpty
            ) {
                await addPair(on: date)
            }
        }
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var sundaysInMonth: [Date] {
        guard let interval = Calendar.current.dateInterval(of: .month, for: month) else {
            return []
        }
        var dates: [Date] = []
        var current = interval.start
        while current < interval.end {
            if Calendar.current.component(.weekday, from: current) == 1 {
                dates.append(current)
            }
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? interval.end
        }
        return dates
    }

    private var monthlyPairCount: Int {
        sessions.filter {
            $0.values.text("session_date").hasPrefix(month.monthKey)
                && !$0.values.flag("removed_from_training")
        }.count
    }

    private func selectionBinding(
        in values: Binding<[String: String]>,
        key: String
    ) -> Binding<String> {
        Binding(
            get: { values.wrappedValue[key] ?? "" },
            set: { values.wrappedValue[key] = $0 }
        )
    }

    private func changeMonth(by value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }

    private func nextMonthKey(_ date: Date) -> String {
        Calendar.current.date(byAdding: .month, value: 1, to: date)?.monthKey
            ?? date.monthKey
    }

    private func load() async {
        loading = sessions.isEmpty
        defer { loading = false }
        do {
            let start = "\(month.monthKey)-01"
            let end = "\(nextMonthKey(month))-01"
            async let loadedSessions = BackendClient.shared.select(
                table: "one_to_one_sessions",
                query: [
                    .init(name: "session_date", value: "gte.\(start)"),
                    .init(name: "session_date", value: "lt.\(end)"),
                    .init(name: "order", value: "session_date.asc")
                ]
            )
            async let loadedStudents = BackendClient.shared.select(
                table: "one_to_one_students",
                query: [
                    .init(name: "active", value: "eq.true"),
                    .init(name: "order", value: "student_name.asc")
                ]
            )
            let users = try? await BackendClient.shared.websiteJSON(path: "/api/users/list")
            let rawSessions = try await loadedSessions
            students = try await loadedStudents
            coaches = users?.object?["users"]?.array?.compactMap(\.object).map(DynamicRecord.init) ?? []
            sessions = rawSessions.map { session in
                var values = session.values
                values["student_name"] = .string(
                    students.first { $0.id == session.values.text("student_id") }?
                        .values.text("student_name", fallback: "Missing student") ?? "Missing student"
                )
                values["coach_name"] = .string(
                    coaches.first { $0.id == session.values.text("coach_id") }
                        .map(displayName) ?? "Unassigned coach"
                )
                return DynamicRecord(values: values)
            }
        } catch {
            state.show(error)
        }
    }

    private func addPair(on date: Date) async {
        guard state.role.permissionRank >= UserRole.admin.permissionRank else {
            state.show("Your account cannot change 1-1 pairings.", kind: .error)
            return
        }
        let activity = state.beginActivity("Adding 1-1 training pair…")
        defer { state.endActivity(activity) }
        let dateKey = date.isoDateKey
        guard let studentID = selectedStudent[dateKey], !studentID.isEmpty,
              let coachID = selectedCoach[dateKey], !coachID.isEmpty else {
            return
        }

        do {
            let existing = try await BackendClient.shared.select(
                table: "one_to_one_sessions",
                query: [
                    .init(name: "session_date", value: "eq.\(dateKey)"),
                    .init(name: "student_id", value: "eq.\(studentID)"),
                    .init(name: "limit", value: "1")
                ]
            ).first

            if let existing, !existing.values.flag("removed_from_training") {
                throw BackendError.message("This student is already paired for that Sunday.")
            }

            let now = ISO8601DateFormatter().string(from: Date())
            let values: JSONObject = [
                "session_date": .string(dateKey),
                "student_id": .string(studentID),
                "coach_id": .string(coachID),
                "removed_from_training": .bool(false),
                "removed_at": .null,
                "payment_exempt": .bool(false),
                "payment_exempt_at": .null,
                "attendance_status": .string("scheduled"),
                "attendance_updated_at": .null,
                "updated_at": .string(now)
            ]

            if let existing {
                _ = try await BackendClient.shared.update(
                    table: "one_to_one_sessions",
                    values: values,
                    filters: [.init(name: "id", value: "eq.\(existing.id)")]
                )
            } else {
                _ = try await BackendClient.shared.insert(
                    table: "one_to_one_sessions",
                    values: values
                )
            }

            if let student = students.first(where: { $0.id == studentID }) {
                let existingPayment = try await BackendClient.shared.select(
                    table: "training_payments",
                    query: [
                        .init(name: "training_student_id", value: "eq.\(studentID)"),
                        .init(name: "week_date", value: "eq.\(dateKey)"),
                        .init(name: "limit", value: "1")
                    ]
                ).first
                _ = try await BackendClient.shared.upsert(
                    table: "training_payments",
                    values: [
                        "training_student_id": .string(studentID),
                        "week_date": .string(dateKey),
                        "paid": .bool(existingPayment?.values.flag("paid") ?? false),
                        "amount": .number(student.values.number("payment_amount", fallback: 80)),
                        "updated_at": .string(now)
                    ],
                    onConflict: "training_student_id,week_date"
                )
            }

            selectedStudent[dateKey] = ""
            selectedCoach[dateKey] = ""
            state.show("Pair added for \(date.formatted(.dateTime.day().month())).")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func displayName(_ record: DynamicRecord) -> String {
        record.values["user_metadata"]?.object?.text(
            "name",
            fallback: record.values.text("email", fallback: "Coach")
        ) ?? record.values.text("email", fallback: "Coach")
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "attended": Theme.green
        case "missed": Theme.red
        case "makeup": Theme.amber
        default: Theme.blue
        }
    }

    private func mark(_ session: DynamicRecord, status: String) async {
        guard state.role.permissionRank >= UserRole.admin.permissionRank else {
            state.show("Your account cannot update 1-1 attendance.", kind: .error)
            return
        }
        let activity = state.beginActivity("Updating training attendance…")
        defer { state.endActivity(activity) }
        do {
            if session.values.text("attendance_status") == "makeup" && status == "scheduled" {
                _ = try await BackendClient.shared.rpc(
                    "undo_one_to_one_makeup_status",
                    params: ["input_session_id": .string(session.id)]
                )
            } else {
                _ = try await BackendClient.shared.update(
                    table: "one_to_one_sessions",
                    values: [
                        "attendance_status": .string(status),
                        "attendance_updated_at": status == "scheduled"
                            ? .null
                            : .string(ISO8601DateFormatter().string(from: Date())),
                        "makeup_target_type": .null,
                        "makeup_usage_id": .null,
                        "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                    ],
                    filters: [.init(name: "id", value: "eq.\(session.id)")]
                )
            }
            await load()
            let name = session.values.text("student_name", fallback: "Student")
            switch status {
            case "attended":
                attendanceSuccessMessage = "\(name) was successfully marked present."
            case "missed":
                attendanceSuccessMessage = "\(name) was successfully marked missed."
            default:
                attendanceSuccessMessage = "\(name)'s latest attendance action was successfully undone."
            }
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func markMakeup(
        _ session: DynamicRecord,
        target: MakeupTargetSelection?
    ) async -> String? {
        guard state.role.permissionRank >= UserRole.admin.permissionRank else {
            state.show("Your account cannot update 1-1 attendance.", kind: .error)
            return nil
        }
        guard session.values.text("attendance_status") == "missed" else {
            state.show("Mark this session as missed before applying a makeup credit.", kind: .error)
            return nil
        }

        let resolvedTarget = target ?? MakeupTargetSelection.defaultTarget(
            forSourceType: "one_to_one",
            date: String(session.values.text("session_date").prefix(10))
        )

        let activity = state.beginActivity("Applying 1-1 makeup credit…")
        defer { state.endActivity(activity) }
        do {
            let creditResponse = try await BackendClient.shared.rpc(
                "find_latest_makeup_credit",
                params: [
                    "input_source_type": .string("one_to_one"),
                    "input_source_student_id": .string(session.values.text("student_id"))
                ]
            )
            guard let credit = firstObject(in: creditResponse),
                  !credit.text("id").isEmpty else {
                throw BackendError.message("No available 1-1 makeup credit was found.")
            }

            let completed = try await BackendClient.shared.rpc(
                "complete_cross_programme_makeup",
                params: [
                    "input_credit_id": .string(credit.text("id")),
                    "input_target_type": .string(resolvedTarget.programme.rawValue),
                    "input_target_date": .string(resolvedTarget.dateKey),
                    "input_target_label": .string(resolvedTarget.label),
                    "input_target_value": .number(resolvedTarget.targetValue)
                ]
            )
            guard let usage = firstObject(in: completed),
                  !usage.text("usage_id").isEmpty else {
                throw BackendError.message("The makeup credit could not be completed.")
            }

            do {
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
                    filters: [.init(name: "id", value: "eq.\(session.id)")]
                )
            } catch {
                _ = try? await BackendClient.shared.rpc(
                    "undo_cross_programme_makeup",
                    params: ["input_usage_id": .string(usage.text("usage_id"))]
                )
                throw error
            }

            await load()
            let name = session.values.text("student_name", fallback: "Student")
            return "\(name) was successfully marked for a \(resolvedTarget.programme.title) makeup."
        } catch {
            state.show(error.localizedDescription, kind: .error)
            return nil
        }
    }

    private func firstObject(in value: JSONValue) -> JSONObject? {
        value.object ?? value.array?.first?.object
    }

    private func remove(_ session: DynamicRecord) async {
        guard state.role.permissionRank >= UserRole.admin.permissionRank else {
            state.show("Your account cannot change 1-1 pairings.", kind: .error)
            return
        }
        let activity = state.beginActivity("Removing training pair…")
        defer { state.endActivity(activity) }
        pendingRemoval = nil
        do {
            _ = try await BackendClient.shared.update(
                table: "one_to_one_sessions",
                values: [
                    "removed_from_training": .bool(true),
                    "removed_at": .string(ISO8601DateFormatter().string(from: Date()))
                ],
                filters: [.init(name: "id", value: "eq.\(session.id)")]
            )
            state.show("Pair removed from the schedule.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }
}

private struct TrainingAttendanceAction {
    let session: DynamicRecord
    let status: String

    var buttonTitle: String {
        switch status {
        case "attended": "Mark Attended"
        case "missed": "Mark Missed"
        case "makeup": "Apply Makeup"
        default: "Undo"
        }
    }

    var message: String {
        let student = session.values.text("student_name", fallback: "this student")
        return switch status {
        case "attended": "Mark \(student)'s session as attended?"
        case "missed": "Mark \(student)'s session as missed and create its makeup credit?"
        case "makeup": "Use the latest available 1-1 makeup credit for \(student)?"
        default: session.values.text("attendance_status") == "makeup"
            ? "Undo this makeup and return the session to Missed?"
            : "Return \(student)'s attendance to Scheduled?"
        }
    }
}
