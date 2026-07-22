import SwiftUI

enum StudentRecordDetailFormatter {
    static func displayableKeys(in values: JSONObject) -> [String] {
        values.keys.sorted().filter { key in
            guard let text = values[key]?.string else { return false }
            return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

struct StudentsView: View {
    @EnvironmentObject private var state: AppState
    @State private var programme: Programme
    @State private var records: [DynamicRecord] = []
    @State private var weekdayPaymentRecords: [DynamicRecord] = []
    @State private var search = ""
    @State private var dayFilter = "All days"
    @State private var timeslotFilter = "All timeslots"
    @State private var levelFilter = "All levels"
    @State private var loading = false
    @State private var pendingRemoval: DynamicRecord?
    private let showsProgrammePicker: Bool
    private let pageTitle: String

    init(
        initialProgramme: Programme = .weekend,
        showsProgrammePicker: Bool = true,
        title: String? = nil
    ) {
        _programme = State(initialValue: initialProgramme)
        self.showsProgrammePicker = showsProgrammePicker
        pageTitle = title ?? "Students"
    }

    private var filtered: [DynamicRecord] {
        records.filter { record in
            guard record.matches(search),
                  programme.includesStudent(
                    active: record.values["active"]?.bool
                  ) else {
                return false
            }
            guard programme == .weekend else { return true }

            let matchesDay = dayFilter == "All days"
                || record.values.text("student_day").caseInsensitiveCompare(dayFilter) == .orderedSame
            let matchesTimeslot = timeslotFilter == "All timeslots"
                || record.values.text("student_timeslot").caseInsensitiveCompare(timeslotFilter) == .orderedSame
            let matchesLevel = levelFilter == "All levels"
                || record.values.text("student_levelofplay").caseInsensitiveCompare(levelFilter) == .orderedSame
            return matchesDay && matchesTimeslot && matchesLevel
        }
    }

    private var hasWeekendFilters: Bool {
        programme == .weekend
            && (dayFilter != "All days"
                || timeslotFilter != "All timeslots"
                || levelFilter != "All levels")
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
                    NavigationLink {
                        AddStudentPage(programme: programme) {
                            await load()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                    .disabled(state.role != .superuser)
                }
                AppSearchField(
                    prompt: programme == .weekend
                        ? "Search Weekend student by name"
                        : "Search students, schedules or fees",
                    text: $search
                )

                if programme == .weekend {
                    WeekendFilterPanel(
                        day: $dayFilter,
                        timeslot: $timeslotFilter,
                        level: $levelFilter
                    )
                }

                HStack {
                    Text(filtered.count == records.filter({
                        programme.includesStudent(
                            active: $0.values["active"]?.bool
                        )
                    }).count
                        ? "\(filtered.count) students"
                        : "Showing \(filtered.count) matching students")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(scope: "\(programme.title) students") {
                        await load()
                    }
                }
                if filtered.isEmpty && !loading {
                    EmptyState(
                        icon: "person.3",
                        title: "No students found",
                        message: search.isEmpty && !hasWeekendFilters
                            ? "Add the first \(programme.title) student."
                            : "Try another name or clear one of the filters."
                    )
                }
                ForEach(filtered) { record in
                    NavigationLink { StudentDetailView(programme: programme, record: record) { await load() } } label: {
                        RecordCard(
                            record: record,
                            titleKeys: ["student_name", "display_name"],
                            detailKeys: detailKeys,
                            query: search,
                            status: programme.includesStudent(
                                active: record.values["active"]?.bool
                            ) ? "Active" : "Inactive"
                        )
                    }
                    .buttonStyle(.plain).contextMenu {
                        if state.role == .superuser { Button("Remove student", systemImage: "person.crop.circle.badge.minus", role: .destructive) { pendingRemoval = record } }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .navigationTitle(pageTitle)
        .refreshable { await load() }
        .task(id: programme) { await load() }
        .alert("Remove this student?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            Button("Remove", role: .destructive) { if let record = pendingRemoval { Task { await remove(record) } } }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { Text("Existing history is retained where supported.") }
        .overlay { if loading { LoadingOverlay(text: "Loading students") } }
    }

    private var detailKeys: [String] {
        switch programme {
        case .weekend: ["student_day", "student_timeslot", "student_levelofplay", "price", "total_weeks", "attended", "missed"]
        case .weekday: [
            "scheduled_sessions",
            "hourly_rate",
            "monthly_payable_hours",
            "total_payment_amount",
            "payment_period"
        ]
        case .matchplay: ["number_of_weeks", "price_per_session"]
        case .oneToOne: ["payment_amount"]
        }
    }

    private func load() async {
        loading = records.isEmpty
        defer { loading = false }
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingWeekdayDashboard"),
           programme == .weekday {
            weekdayPaymentRecords = []
            records = [weekdayDashboardRecord(DynamicRecord(values: [
                "id": .string("ui-test-weekday-dashboard-student"),
                "student_name": .string("Brandon Teo"),
                "hourly_rate": .number(80),
                "schedules": .array([
                    .object(["day": .string("Wednesday"), "duration_hours": .number(2)]),
                    .object(["day": .string("Thursday"), "duration_hours": .number(1)])
                ]),
                "active": .bool(true)
            ]))]
            return
        }
#endif
        do {
            if programme == .weekend {
                records = try await BackendClient.shared.weekendStudents(
                    paths: WeekendStudentWebsiteRoute.dashboardSources
                )
                return
            }
            var query = [URLQueryItem(
                name: "order",
                value: "student_name.asc"
            )]
            if let activeFilter = programme.activeStudentFilter {
                query.insert(activeFilter, at: 0)
            }
            if programme == .weekday {
                let studentQuery = query
                async let loadedStudents = BackendClient.shared.select(
                    table: programme.studentTable,
                    query: studentQuery
                )
                async let loadedPayments = BackendClient.shared.select(
                    table: programme.paymentTable,
                    query: [
                        .init(name: "payment_month", value: "eq.\(weekdayDashboardMonth.monthKey)"),
                        .init(name: "order", value: "day_name.asc")
                    ]
                )
                let students = try await loadedStudents
                weekdayPaymentRecords = try await loadedPayments
                records = students.map(weekdayDashboardRecord)
            } else {
                records = try await BackendClient.shared.select(
                    table: programme.studentTable,
                    query: query
                )
            }
        } catch { state.show(error) }
    }

    private func weekdayDashboardRecord(_ record: DynamicRecord) -> DynamicRecord {
        let schedules = record.values["schedules"]?.array?
            .compactMap(\.object) ?? []
        let manualHours = weekdayPaymentRecords.reduce(into: [String: Double]()) {
            result, payment in
            guard payment.values.text("weekday_student_id") == record.id,
                  let hours = payment.values["manual_hours"]?.double else {
                return
            }
            result[payment.values.text("day_name")] = hours
        }
        let rate = record.values.number("hourly_rate", fallback: 80)
        let summary = WeekdayMonthlyPaymentCalculator.summary(
            schedules: schedules,
            hourlyRate: rate,
            month: weekdayDashboardMonth,
            manualHoursByDay: manualHours
        )

        var values = record.values
        values["scheduled_sessions"] = .string(
            schedules.map { schedule in
                let hours = schedule.number(
                    "duration_hours",
                    fallback: schedule.number("duration", fallback: 1)
                )
                return "\(schedule.text("day")) · \(numberLabel(hours))h"
            }
            .joined(separator: ", ")
        )
        values["monthly_payable_hours"] = .number(summary.payableHours)
        values["total_payment_amount"] = .number(summary.amount)
        values["payment_period"] = .string(
            weekdayDashboardMonth.formatted(.dateTime.month(.wide).year())
        )
        return DynamicRecord(values: values)
    }

    private var weekdayDashboardMonth: Date {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingWeekdayDashboard") {
            return Calendar.current.date(
                from: DateComponents(year: 2026, month: 7, day: 15)
            ) ?? Date()
        }
#endif
        return Date()
    }

    private func numberLabel(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private func remove(_ record: DynamicRecord) async {
        guard state.role == .superuser else {
            state.show("Only superusers can remove students from a dashboard.", kind: .error)
            return
        }
        let activity = state.beginActivity("Removing student…")
        defer { state.endActivity(activity) }
        defer { pendingRemoval = nil }
        do {
            if programme == .weekend {
                _ = try await BackendClient.shared.websiteJSON(path: "/api/students/delete", method: "POST", body: ["student_id": .string(record.values.text("student_id"))])
            } else {
                _ = try await BackendClient.shared.update(table: programme.studentTable, values: ["active": .bool(false), "updated_at": .string(ISO8601DateFormatter().string(from: Date()))], filters: [.init(name: "id", value: "eq.\(record.id)")])
            }
            state.show("Student removed."); await load()
        } catch { state.show(error.localizedDescription, kind: .error) }
    }
}

struct AddStudentPage: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    let programme: Programme
    var showsDashboardAfterSave = false
    let onSaved: () async -> Void
    @State private var didSave = false
    @State private var name = ""
    @State private var day = "Saturday"
    @State private var timeslot = "2-4pm"
    @State private var level = "Beginner"
    @State private var price: Double
    @State private var weeks: Int
    @State private var selectedDays: Set<String> = ["Monday"]
    @State private var hours: [String: Double] = ["Monday": 1, "Wednesday": 1, "Thursday": 1]

    init(
        programme: Programme,
        showsDashboardAfterSave: Bool = false,
        onSaved: @escaping () async -> Void = {}
    ) {
        self.programme = programme
        self.showsDashboardAfterSave = showsDashboardAfterSave
        self.onSaved = onSaved
        _price = State(initialValue: programme == .weekend ? 40 : 80)
        _weeks = State(initialValue: programme == .weekend ? 10 : 4)
    }

    var body: some View {
        Group {
            if didSave && showsDashboardAfterSave {
                StudentsView(
                    initialProgramme: programme,
                    showsProgrammePicker: false,
                    title: "\(programme.title) Dashboard"
                )
            } else {
                addForm
            }
        }
    }

    private var addForm: some View {
            Form {
                Section("Student") { TextField("Full name", text: $name).textInputAutocapitalization(.words) }
                switch programme {
                case .weekend:
                    Section("Training") {
                        Picker("Day", selection: $day) { Text("Saturday").tag("Saturday"); Text("Sunday").tag("Sunday") }
                        Picker("Timeslot", selection: $timeslot) {
                            ForEach(WeekendSchedule.timeslots(for: day), id: \.self) {
                                Text($0)
                            }
                        }
                        Picker("Student Level of Play", selection: $level) { ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { Text($0) } }
                        if state.role == .superuser {
                            LabeledContent("Price") { TextField("Price", value: $price, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                            InlineNumberStepper(title: "Total weeks", value: $weeks, range: 1...52)
                        } else {
                            LabeledContent("Price", value: "$40")
                            LabeledContent("Total weeks", value: "10")
                        }
                    }
                case .weekday:
                    Section("Weekly sessions") {
                        ForEach(["Monday", "Wednesday", "Thursday"], id: \.self) { weekday in
                            Toggle(weekday, isOn: Binding(
                                get: { selectedDays.contains(weekday) },
                                set: { isSelected in
                                    if isSelected { selectedDays.insert(weekday) }
                                    else { selectedDays.remove(weekday) }
                                }
                            ))
                            if selectedDays.contains(weekday) {
                                InlineDecimalStepper(
                                    title: "Hours",
                                    value: Binding(get: { hours[weekday] ?? 1 }, set: { hours[weekday] = $0 }),
                                    range: 0.5...8,
                                    step: 0.5
                                )
                            }
                        }
                        if state.role == .superuser {
                            LabeledContent("Hourly rate") {
                                TextField("Rate", value: $price, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        } else {
                            LabeledContent("Hourly rate", value: "$80")
                        }
                    }
                case .matchplay:
                    Section("MatchPlay") {
                        InlineNumberStepper(title: "Number of weeks", value: $weeks, range: 1...52)
                        if state.role == .superuser {
                            LabeledContent("Price per session") {
                                TextField("Price", value: $price, format: .number)
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                            }
                        } else {
                            LabeledContent("Price per session", value: "$80")
                        }
                    }
                case .oneToOne:
                    Section("1-1") {
                        if state.role == .superuser {
                            LabeledContent("Payment amount") { TextField("Amount", value: $price, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing) }
                        } else {
                            LabeledContent("Payment amount", value: "$80")
                        }
                    }
                }
                Section {
                    AsyncActionButton(
                        title: "Add \(programme.title) student",
                        progressTitle: "Adding student…",
                        icon: "plus",
                        disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (programme == .weekday && selectedDays.isEmpty)
                    ) { await save() }
                }
            }
            .navigationTitle("Add \(programme.title) Student")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: day) { _, newDay in
                let slots = WeekendSchedule.timeslots(for: newDay)
                if !slots.contains(timeslot) {
                    timeslot = slots.first ?? ""
                }
            }
        }

    private func save() async {
        guard state.role != .member else {
            state.show("Your account cannot add students.", kind: .error)
            return
        }
        let activity = state.beginActivity("Adding \(programme.title) student…")
        defer { state.endActivity(activity) }
        let now = ISO8601DateFormatter().string(from: Date())
        let defaultPrice = programme == .weekend ? 40.0 : 80.0
        let priceToSave = state.role == .superuser ? price : defaultPrice
        let weeksToSave = programme == .weekend && state.role != .superuser ? 10 : weeks
        var values: JSONObject = ["student_name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)), "updated_at": .string(now)]
        if programme != .weekend { values["active"] = .bool(true) }
        switch programme {
        case .weekend:
            values.merge(["student_id": .string(UUID().uuidString), "student_day": .string(day), "student_timeslot": .string(timeslot), "student_levelofplay": .string(level), "price": .number(priceToSave), "total_weeks": .number(Double(weeksToSave)), "weeks_completed": .number(0), "attended": .number(0), "missed": .number(0), "created_at": .string(now)]) { _, new in new }
        case .weekday:
            let schedules = selectedDays.sorted().map { JSONValue.object(["day": .string($0), "duration_hours": .number(hours[$0] ?? 1)]) }
            let monthlySummary = WeekdayMonthlyPaymentCalculator.summary(
                schedules: schedules.compactMap(\.object),
                hourlyRate: priceToSave,
                month: Date()
            )
            values.merge([
                "schedules": .array(schedules),
                "hourly_rate": .number(priceToSave),
                "total_payment_amount": .number(monthlySummary.amount)
            ]) { _, new in new }
        case .matchplay: values.merge(["number_of_weeks": .number(Double(weeksToSave)), "price_per_session": .number(priceToSave)]) { _, new in new }
        case .oneToOne: values["payment_amount"] = .number(priceToSave)
        }
        do {
            _ = try await BackendClient.shared.insert(table: programme.studentTable, values: values)
            state.show("Student added.")
            await onSaved()
            if showsDashboardAfterSave {
                didSave = true
            } else {
                dismiss()
            }
        }
        catch { state.show(error.localizedDescription, kind: .error) }
    }
}

private struct StudentDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState
    let programme: Programme
    let record: DynamicRecord
    let onChanged: () async -> Void
    @State private var name = ""
    @State private var amount = 0.0
    @State private var weeks = 0
    @State private var day = "Saturday"
    @State private var timeslot = "2-4pm"
    @State private var level = "Beginner"
    @State private var selectedDays: Set<String> = []
    @State private var hours: [String: Double] = [:]
    @State private var showDeleteConfirmation = false

    var body: some View {
        Form {
            Section("Student") {
                if state.role != .superuser {
                    LabeledContent("Name", value: name)
                } else {
                    TextField("Name", text: $name)
                }
                LabeledContent("Programme", value: programme.title)
            }
            if state.role == .superuser {
                Section("Editable values") {
                    switch programme {
                    case .weekend:
                        Picker("Day", selection: $day) {
                            Text("Saturday").tag("Saturday")
                            Text("Sunday").tag("Sunday")
                        }
                        Picker("Timeslot", selection: $timeslot) {
                            ForEach(WeekendSchedule.timeslots(for: day), id: \.self) { Text($0) }
                        }
                        Picker("Student Level of Play", selection: $level) {
                            ForEach(["Beginner", "Intermediate", "Advanced"], id: \.self) { Text($0) }
                        }
                        InlineNumberStepper(title: "Total weeks", value: $weeks, range: 1...104)
                        LabeledContent("Price") {
                            TextField("Price", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    case .weekday:
                        ForEach(["Monday", "Wednesday", "Thursday"], id: \.self) { weekday in
                            Toggle(weekday, isOn: Binding(
                                get: { selectedDays.contains(weekday) },
                                set: { selected in
                                    if selected { selectedDays.insert(weekday) }
                                    else { selectedDays.remove(weekday) }
                                }
                            ))
                            if selectedDays.contains(weekday) {
                                InlineDecimalStepper(
                                    title: "Hours",
                                    value: Binding(
                                        get: { hours[weekday] ?? 1 },
                                        set: { hours[weekday] = $0 }
                                    ),
                                    range: 0.25...8,
                                    step: 0.25
                                )
                            }
                        }
                        LabeledContent("Hourly rate") {
                            TextField("Rate", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    case .matchplay:
                        InlineNumberStepper(title: "Number of weeks", value: $weeks, range: 1...104)
                        LabeledContent("Price per session") {
                            TextField("Price", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    case .oneToOne:
                        LabeledContent("Payment amount") {
                            TextField("Amount", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    AsyncActionButton(
                        title: "Save changes",
                        progressTitle: "Saving changes…",
                        icon: "checkmark",
                        disabled: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (programme == .weekday && selectedDays.isEmpty)
                    ) { await save() }
                }
            }
            Section("Record details") {
                ForEach(
                    StudentRecordDetailFormatter.displayableKeys(in: record.values),
                    id: \.self
                ) { key in
                    LabeledContent(displayLabel(key), value: record.values.text(key))
                }
            }
            if state.role == .superuser {
                Section {
                    Button("Delete student", systemImage: "trash", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                    .buttonStyle(.plain)
                } footer: {
                    Text("Attendance and payment history is retained where supported.")
                }
            }
        }
        .navigationTitle(record.values.text("student_name", fallback: "Student"))
        .alert("Delete this student?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) { Task { await remove() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the student from the active programme list.")
        }
        .onChange(of: day) { _, newDay in
            let slots = WeekendSchedule.timeslots(for: newDay)
            if !slots.contains(timeslot) {
                timeslot = slots.first ?? ""
            }
        }
        .onAppear {
            name = record.values.text("student_name")
            amount = record.values.number(programme == .weekday ? "hourly_rate" : programme == .oneToOne ? "payment_amount" : programme == .matchplay ? "price_per_session" : "price")
            weeks = Int(record.values.number(programme == .matchplay ? "number_of_weeks" : "total_weeks"))
            day = record.values.text("student_day", fallback: "Saturday")
            timeslot = record.values.text("student_timeslot", fallback: WeekendSchedule.timeslots(for: day).first ?? "")
            if !WeekendSchedule.timeslots(for: day).contains(timeslot) {
                timeslot = WeekendSchedule.timeslots(for: day).first ?? ""
            }
            level = record.values.text("student_levelofplay", fallback: "Beginner")
            let schedules = record.values["schedules"]?.array?.compactMap(\.object) ?? []
            selectedDays = Set(schedules.map { $0.text("day") })
            hours = Dictionary(uniqueKeysWithValues: schedules.map {
                ($0.text("day"), $0.number("duration_hours", fallback: 1))
            })
        }
    }

    private func save() async {
        guard state.role == .superuser else {
            state.show("Only superusers can change student details or pricing.", kind: .error)
            return
        }
        let activity = state.beginActivity("Saving student changes…")
        defer { state.endActivity(activity) }
        let idKey = programme == .weekend ? "student_id" : "id"
        var values: JSONObject = [
            "student_name": .string(name.trimmingCharacters(in: .whitespacesAndNewlines)),
            programme == .weekday ? "hourly_rate" : programme == .oneToOne ? "payment_amount" : programme == .matchplay ? "price_per_session" : "price": .number(amount),
            "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
        ]
        if programme == .weekend {
            values.merge([
                "student_day": .string(day),
                "student_timeslot": .string(timeslot),
                "student_levelofplay": .string(level),
                "total_weeks": .number(Double(weeks))
            ]) { _, new in new }
        }
        if programme == .matchplay { values["number_of_weeks"] = .number(Double(weeks)) }
        if programme == .weekday {
            let schedules = selectedDays.sorted().map {
                JSONValue.object([
                    "day": .string($0),
                    "duration_hours": .number(hours[$0] ?? 1)
                ])
            }
            let monthlySummary = WeekdayMonthlyPaymentCalculator.summary(
                schedules: schedules.compactMap(\.object),
                hourlyRate: amount,
                month: Date()
            )
            values["schedules"] = .array(schedules)
            values["total_payment_amount"] = .number(monthlySummary.amount)
        }
        do { _ = try await BackendClient.shared.update(table: programme.studentTable, values: values, filters: [.init(name: idKey, value: "eq.\(record.values.text(idKey))")]); state.show("Student updated."); await onChanged() }
        catch { state.show(error.localizedDescription, kind: .error) }
    }

    private func remove() async {
        guard state.role == .superuser else {
            state.show("Only superusers can delete students.", kind: .error)
            return
        }
        let activity = state.beginActivity("Deleting student…")
        defer { state.endActivity(activity) }
        do {
            if programme == .weekend {
                _ = try await BackendClient.shared.websiteJSON(
                    path: "/api/students/delete",
                    method: "POST",
                    body: ["student_id": .string(record.values.text("student_id"))]
                )
            } else {
                _ = try await BackendClient.shared.update(
                    table: programme.studentTable,
                    values: [
                        "active": .bool(false),
                        "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                    ],
                    filters: [.init(name: "id", value: "eq.\(record.id)")]
                )
            }
            state.show("Student deleted.")
            await onChanged()
            dismiss()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func displayLabel(_ key: String) -> String {
        if key == "student_levelofplay" { return "Student Level of Play" }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

enum WeekendSchedule {
    static let saturdayTimeslots = ["2-4pm", "4-6pm"]
    static let sundayTimeslots = ["8-10am", "10-12pm", "1-3pm", "3-5pm"]

    static func timeslots(for day: String) -> [String] {
        day == "Saturday" ? saturdayTimeslots : sundayTimeslots
    }

    static var allTimeslots: [String] {
        saturdayTimeslots + sundayTimeslots
    }
}
