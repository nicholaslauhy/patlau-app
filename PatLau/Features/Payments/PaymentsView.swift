import SwiftUI

enum PaymentWebsiteRoute {
    static let ensureWeekendHistory = "/api/create-payment-table"
    static let ensureWeekendHistoryMethod = "POST"
}

struct WeekendPaymentQuarter: Equatable {
    let start: Date
    let end: Date

    static func new(
        startingAt date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WeekendPaymentQuarter {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 3, to: start)
            ?? date.addingTimeInterval(90 * 24 * 60 * 60)
        return WeekendPaymentQuarter(start: start, end: end)
    }

    func advanced(
        to date: Date,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> WeekendPaymentQuarter {
        guard end > start else {
            return Self.new(startingAt: date, calendar: calendar)
        }

        var nextStart = start
        var nextEnd = end
        while date >= nextEnd {
            nextStart = nextEnd
            nextEnd = calendar.date(byAdding: .month, value: 3, to: nextStart)
                ?? nextStart.addingTimeInterval(90 * 24 * 60 * 60)
        }
        return WeekendPaymentQuarter(start: nextStart, end: nextEnd)
    }
}

enum PaymentTrackingCadence: Equatable {
    case calendarMonth
    case rollingThreeMonths
}

struct CalendarMonthPaymentPeriod: Equatable {
    let start: Date
    let end: Date

    static func containing(
        _ date: Date,
        calendar: Calendar = .current
    ) -> CalendarMonthPaymentPeriod {
        if let interval = calendar.dateInterval(of: .month, for: date) {
            return CalendarMonthPaymentPeriod(
                start: interval.start,
                end: interval.end
            )
        }

        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .month, value: 1, to: start)
            ?? start.addingTimeInterval(31 * 24 * 60 * 60)
        return CalendarMonthPaymentPeriod(start: start, end: end)
    }
}

enum MonthlyPaymentCounter {
    static func includes(
        paid: Bool,
        paymentTimestamp: Date?,
        resetAt: Date?
    ) -> Bool {
        guard paid else { return false }
        guard let resetAt else { return true }
        guard let paymentTimestamp else { return false }
        return paymentTimestamp >= resetAt
    }
}

struct PaymentRefreshPlan: Equatable {
    let programme: Programme

    var label: String { "\(programme.title) payments" }

    var trackingCadence: PaymentTrackingCadence {
        programme == .weekend ? .rollingThreeMonths : .calendarMonth
    }

    var resources: Set<String> {
        switch programme {
        case .weekend:
            ["students", "weekend_payment_period_state", "payment_history"]
        case .weekday:
            ["weekday_students", "weekday_payments", "payment_counter_state"]
        case .matchplay:
            ["matchplay_students", "matchplay_payments", "payment_counter_state"]
        case .oneToOne:
            [
                "one_to_one_sessions",
                "one_to_one_students",
                "training_payments",
                "payment_counter_state"
            ]
        }
    }
}

struct PaymentsView: View {
    @EnvironmentObject private var state: AppState

    @State private var programme: Programme
    @State private var filter: PaymentFilter = .all
    @State private var month = Date()
    @State private var rows: [DynamicRecord] = []
    @State private var students: [DynamicRecord] = []
    @State private var paymentRecords: [DynamicRecord] = []
    @State private var weekendQuarter: WeekendPaymentQuarter?
    @State private var monthlyCounterResetAt: Date?
    @State private var search = ""
    @State private var loading = false
    @State private var pendingToggle: DynamicRecord?
    @State private var adjustingRow: DynamicRecord?
    @State private var showResetConfirmation = false
    @State private var showUndoConfirmation = false

    private let showsProgrammePicker: Bool

    init(
        initialProgramme: Programme = .weekend,
        showsProgrammePicker: Bool = true
    ) {
        _programme = State(initialValue: initialProgramme)
        self.showsProgrammePicker = showsProgrammePicker
    }

    private var filteredRows: [DynamicRecord] {
        rows.filter { row in
            row.matches(search)
                && (filter == .all || isPaid(row) == (filter == .paid))
        }
    }

    private var paidRows: [DynamicRecord] { rows.filter(isPaid) }
    private var monthlyCounterPayments: [DynamicRecord] {
        paymentRecords.filter { payment in
            MonthlyPaymentCounter.includes(
                paid: payment.values.flag("paid"),
                paymentTimestamp: paymentTimestamp(payment),
                resetAt: monthlyCounterResetAt
            )
        }
    }
    private var collected: Double {
        if programme == .weekend {
            return paymentRecords.reduce(0) { $0 + $1.values.number("amount") }
        }
        return monthlyCounterPayments.reduce(0) {
            $0 + $1.values.number("amount")
        }
    }
    private var fullPeriodCollected: Double {
        if programme == .weekend { return collected }
        return paidRows.reduce(0) { $0 + $1.values.number("amount") }
    }
    private var possible: Double { rows.reduce(0) { $0 + $1.values.number("amount") } }

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
                    if programme != .weekend {
                        HStack(spacing: 12) {
                            Button { changeMonth(by: -1) } label: {
                                Image(systemName: "chevron.left")
                                    .frame(width: 32, height: 40)
                            }
                            .buttonStyle(.plain)

                            Text(month.formatted(.dateTime.month(.abbreviated).year()))
                                .font(.subheadline.weight(.semibold))

                            Button { changeMonth(by: 1) } label: {
                                Image(systemName: "chevron.right")
                                    .frame(width: 32, height: 40)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                summaryCard

                FilterChips(
                    values: PaymentFilter.allCases.map { $0.rawValue.capitalized },
                    selection: Binding(
                        get: { filter.rawValue.capitalized },
                        set: { filter = PaymentFilter(rawValue: $0.lowercased()) ?? .all }
                    )
                )

                TextField("Search student, session or payment", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)

                HStack {
                    Text("\(filteredRows.count) payment record\(filteredRows.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(scope: paymentRefreshPlan.label) {
                        await load()
                    }
                }

                if filteredRows.isEmpty && !loading {
                    EmptyState(
                        icon: "dollarsign.circle",
                        title: "No payment rows",
                        message: "No students or sessions match this month and filter."
                    )
                }

                if !filteredRows.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(filteredRows.enumerated()), id: \.offset) { index, row in
                            compactPaymentRow(row)
                            if index < filteredRows.count - 1 {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("\(programme.title) Payments")
        .task(id: paymentLoadKey) { await load() }
        .refreshable { await load() }
        .alert(
            isPaid(pendingToggle) ? "Reverse this payment?" : "Record this payment?",
            isPresented: Binding(
                get: { pendingToggle != nil },
                set: { if !$0 { pendingToggle = nil } }
            )
        ) {
            Button(isPaid(pendingToggle) ? "Mark Unpaid" : "Mark Paid") {
                if let row = pendingToggle {
                    Task { await setPaid(row, paid: !isPaid(row)) }
                }
            }
            Button("Cancel", role: .cancel) { pendingToggle = nil }
        } message: {
            Text("The app will update the same payment records and send the same Telegram notification as the website.")
        }
        .sheet(item: $adjustingRow) { row in
            PaymentAdjustmentSheet(
                programme: programme,
                row: row,
                student: studentForAdjustment(row),
                paymentRecords: paymentRecords,
                month: month
            ) { adjustment in
                await saveAdjustment(adjustment, for: row)
            }
        }
        .alert(
            resetConfirmationTitle,
            isPresented: $showResetConfirmation
        ) {
            Button("Send Summary and Reset", role: .destructive) {
                Task { await resetDisplayedTotal() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(resetConfirmationMessage)
        }
        .alert(
            "Undo the latest payment?",
            isPresented: $showUndoConfirmation
        ) {
            Button("Undo Latest", role: .destructive) { Task { await undoLatest() } }
            Button("Cancel", role: .cancel) {}
        }
        .overlay { if loading { LoadingOverlay(text: "Loading payments") } }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                programme == .weekend
                    ? "Weekend quarterly payments"
                    : "\(programme.title) monthly payments"
            )
                .font(.headline)
            Text(collected, format: .currency(code: "SGD"))
                .font(.largeTitle.bold())
                .foregroundStyle(Theme.blue)
            if programme == .weekend {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Quarterly tracking period", systemImage: "calendar.badge.clock")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(weekendQuarterLabel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                    Text("Weekend collections are totalled within this rolling three-month quarter.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Monthly tracking period", systemImage: "calendar")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.ink)
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                    Text(monthlyPeriodLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.secondaryText)
                    Text("\(programme.title) collections are totalled within this calendar month.")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    if let monthlyCounterResetAt {
                        Text("Displayed counter restarted \(monthlyCounterResetAt.formatted(date: .abbreviated, time: .shortened)); payment statuses were preserved.")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            Text("\(paidRows.count) paid • \(rows.count - paidRows.count) unpaid • \(possible.formatted(.currency(code: "SGD"))) possible")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            PaymentCounterActions(
                canUndo: hasUndoablePayment,
                onReset: { showResetConfirmation = true },
                onUndo: { showUndoConfirmation = true }
            )
        }
        .appCard()
    }

    private var weekendQuarterLabel: String {
        guard let weekendQuarter else {
            return "Loading tracking period…"
        }
        let start = weekendQuarter.start.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        let end = weekendQuarter.end.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        return "\(start) – \(end)"
    }

    private var monthlyPeriodLabel: String {
        let period = CalendarMonthPaymentPeriod.containing(month)
        let finalDay = Calendar.current.date(
            byAdding: .day,
            value: -1,
            to: period.end
        ) ?? period.end
        let start = period.start.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        let end = finalDay.formatted(
            .dateTime.day().month(.abbreviated).year()
        )
        return "\(start) – \(end)"
    }

    private var paymentRefreshPlan: PaymentRefreshPlan {
        PaymentRefreshPlan(programme: programme)
    }

    private var paymentLoadKey: String {
        programme == .weekend
            ? programme.rawValue
            : "\(programme.rawValue)-\(month.monthKey)"
    }

    private var resetConfirmationTitle: String {
        programme == .weekend
            ? "Close this quarterly tracking period?"
            : "Send a summary and reset the displayed total?"
    }

    private var resetConfirmationMessage: String {
        if programme == .weekend {
            return "This sends the summary for \(weekendQuarterLabel) and starts a new rolling three-month quarter today. Existing payment statuses and history stay unchanged."
        }
        return "This sends the full \(month.formatted(.dateTime.month(.wide).year())) summary and resets only that month's displayed counter. Existing paid and unpaid statuses stay unchanged."
    }

    @ViewBuilder
    private func compactPaymentRow(_ row: DynamicRecord) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.values.text("student_name", fallback: "Student"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(paymentSummary(row))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Text(row.values.number("amount"), format: .currency(code: "SGD"))
                    .font(.subheadline.weight(.semibold))
                StatusBadge(
                    text: isPaid(row) ? "Paid" : "Unpaid",
                    color: isPaid(row) ? Theme.green : Theme.red
                )
            }

            Menu {
                Button(isPaid(row) ? "Mark Unpaid" : "Mark Paid") {
                    pendingToggle = row
                }
                if programme != .weekend {
                    Button("Adjust Payment", systemImage: "slider.horizontal.3") {
                        adjustingRow = row
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.semibold))
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Payment actions for \(row.values.text("student_name", fallback: "student"))")
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func paymentSummary(_ row: DynamicRecord) -> String {
        switch programme {
        case .weekend:
            return [row.values.text("student_day"), row.values.text("student_timeslot")]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
        case .weekday:
            return "\(row.values.text("days")) • \(row.values.number("payable_hours").formatted()) payable hours"
        case .matchplay:
            return "\(Int(row.values.number("weeks"))) weeks • \(row.values.number("price_per_session").formatted(.currency(code: "SGD")))/session"
        case .oneToOne:
            return [row.values.text("session_date"), row.values.text("coach_name")]
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
        }
    }

    private var detailKeys: [String] {
        switch programme {
        case .weekend:
            ["student_day", "student_timeslot", "student_levelofplay", "price", "total_weeks", "amount"]
        case .weekday:
            ["days", "sessions", "payable_hours", "rate", "amount"]
        case .matchplay:
            ["weeks", "price_per_session", "amount"]
        case .oneToOne:
            ["session_date", "coach_name", "training_status", "amount"]
        }
    }

    private var hasUndoablePayment: Bool {
        switch programme {
        case .weekend:
            !paymentRecords.isEmpty
        default:
            paymentRecords.contains { $0.values.flag("paid") }
        }
    }

    private func isPaid(_ row: DynamicRecord?) -> Bool {
        row?.values.flag("paid") ?? false
    }

    private func load() async {
        loading = rows.isEmpty
        defer { loading = false }

        do {
            switch paymentRefreshPlan.programme {
            case .weekend:
                try await loadWeekend()
            case .weekday:
                try await loadWeekday()
            case .matchplay:
                try await loadMatchPlay()
            case .oneToOne:
                try await loadOneToOne()
            }
        } catch {
            state.show(error)
        }
    }

    private func loadWeekend() async throws {
        monthlyCounterResetAt = nil
        async let loadedStudents = BackendClient.shared.weekendStudents(
            path: WeekendStudentWebsiteRoute.payments
        )
        students = try await loadedStudents

        let periodRows = try await BackendClient.shared.select(
            table: "weekend_payment_period_state",
            query: [.init(name: "id", value: "eq.1")]
        )
        let period = try await resolveWeekendQuarter(from: periodRows.first)
        weekendQuarter = period
        paymentRecords = try await BackendClient.shared.select(
            table: "payment_history",
            query: [
                .init(name: "recorded_at", value: "gte.\(isoString(period.start))"),
                .init(name: "recorded_at", value: "lt.\(isoString(period.end))"),
                .init(name: "order", value: "recorded_at.desc")
            ]
        )
        rows = students.map { student in
            var values = student.values
            values["id"] = .string(student.values.text("student_id", fallback: student.id))
            values["amount"] = .number(
                student.values.number("price") * max(1, student.values.number("total_weeks"))
            )
            return DynamicRecord(values: values)
        }
    }

    private func resolveWeekendQuarter(
        from record: DynamicRecord?
    ) async throws -> WeekendPaymentQuarter {
        let stored: WeekendPaymentQuarter?
        if let record,
           let start = parseISODate(record.values.text("start_at")),
           let end = parseISODate(record.values.text("end_at")),
           end > start {
            stored = WeekendPaymentQuarter(start: start, end: end)
        } else {
            stored = nil
        }

        let period = (stored ?? .new(startingAt: Date())).advanced(to: Date())
        if stored != period {
            let now = isoString(Date())
            _ = try await BackendClient.shared.upsert(
                table: "weekend_payment_period_state",
                values: [
                    "id": .number(1),
                    "start_at": .string(isoString(period.start)),
                    "end_at": .string(isoString(period.end)),
                    "updated_at": .string(now)
                ],
                onConflict: "id"
            )
        }
        return period
    }

    private func loadWeekday() async throws {
        async let loadedStudents = BackendClient.shared.select(
            table: "weekday_students",
            query: [
                .init(name: "active", value: "eq.true"),
                .init(name: "order", value: "student_name.asc")
            ]
        )
        async let loadedPayments = BackendClient.shared.select(
            table: "weekday_payments",
            query: [
                .init(name: "payment_month", value: "eq.\(month.monthKey)"),
                .init(name: "order", value: "day_name.asc")
            ]
        )
        async let loadedCounterResetAt = loadMonthlyCounterResetAt(
            programme: .weekday,
            month: month
        )
        students = try await loadedStudents
        paymentRecords = try await loadedPayments
        monthlyCounterResetAt = try await loadedCounterResetAt

        rows = students.compactMap { student in
            let schedules = student.values["schedules"]?.array?.compactMap(\.object) ?? []
            guard !schedules.isEmpty else { return nil }
            let rate = student.values.number("hourly_rate", fallback: 80)
            var totalSessions = 0
            var payableHours = 0.0
            var amount = 0.0
            var allPaid = true

            for schedule in schedules {
                let day = schedule.text("day")
                let duration = schedule.number("duration_hours", fallback: schedule.number("duration", fallback: 1))
                let occurrences = weekdayOccurrences(day: day, month: month)
                let scheduledHours = duration * Double(occurrences)
                let payment = paymentRecords.first {
                    $0.values.text("weekday_student_id") == student.id
                        && $0.values.text("day_name") == day
                }
                let hours = payment?.values["manual_hours"]?.double ?? scheduledHours
                totalSessions += occurrences
                payableHours += hours
                amount += hours * rate
                allPaid = allPaid && (payment?.values.flag("paid") ?? false)
            }

            var values = student.values
            values.merge([
                "id": .string("weekday-\(student.id)-\(month.monthKey)"),
                "source_student_id": .string(student.id),
                "days": .string(schedules.map { $0.text("day") }.joined(separator: ", ")),
                "sessions": .number(Double(totalSessions)),
                "payable_hours": .number(payableHours),
                "rate": .number(rate),
                "amount": .number(amount),
                "paid": .bool(allPaid)
            ]) { _, new in new }
            return DynamicRecord(values: values)
        }
    }

    private func loadMatchPlay() async throws {
        async let loadedStudents = BackendClient.shared.select(
            table: "matchplay_students",
            query: [
                .init(name: "active", value: "eq.true"),
                .init(name: "order", value: "student_name.asc")
            ]
        )
        async let loadedPayments = BackendClient.shared.select(
            table: "matchplay_payments",
            query: [
                .init(name: "payment_month", value: "eq.\(month.monthKey)"),
                .init(name: "order", value: "updated_at.desc")
            ]
        )
        async let loadedCounterResetAt = loadMonthlyCounterResetAt(
            programme: .matchplay,
            month: month
        )
        students = try await loadedStudents
        paymentRecords = try await loadedPayments
        monthlyCounterResetAt = try await loadedCounterResetAt
        rows = students.map { student in
            let payment = paymentRecords.first {
                $0.values.text("matchplay_student_id") == student.id
            }
            let weeks = payment?.values["manual_weeks"]?.double
                ?? student.values.number("number_of_weeks")
            let rate = payment?.values["manual_price_per_session"]?.double
                ?? student.values.number("price_per_session")
            var values = student.values
            values.merge([
                "id": .string("matchplay-\(student.id)-\(month.monthKey)"),
                "source_student_id": .string(student.id),
                "weeks": .number(weeks),
                "price_per_session": .number(rate),
                "amount": .number(weeks * rate),
                "paid": .bool(payment?.values.flag("paid") ?? false)
            ]) { _, new in new }
            return DynamicRecord(values: values)
        }
    }

    private func loadOneToOne() async throws {
        let start = "\(month.monthKey)-01"
        let end = nextMonthKey(month)
        async let loadedSessions = BackendClient.shared.select(
            table: "one_to_one_sessions",
            query: [
                .init(name: "or", value: "(payment_exempt.is.null,payment_exempt.eq.false)"),
                .init(name: "session_date", value: "gte.\(start)"),
                .init(name: "session_date", value: "lt.\(end)-01"),
                .init(name: "order", value: "session_date.asc")
            ]
        )
        async let loadedStudents = BackendClient.shared.select(table: "one_to_one_students")
        async let loadedPayments = BackendClient.shared.select(
            table: "training_payments",
            query: [
                .init(name: "week_date", value: "gte.\(start)"),
                .init(name: "week_date", value: "lt.\(end)-01"),
                .init(name: "order", value: "week_date.desc")
            ]
        )
        async let loadedCounterResetAt = loadMonthlyCounterResetAt(
            programme: .oneToOne,
            month: month
        )
        let sessions = try await loadedSessions
        students = try await loadedStudents
        paymentRecords = try await loadedPayments
        monthlyCounterResetAt = try await loadedCounterResetAt
        rows = sessions.map { session in
            let student = students.first { $0.id == session.values.text("student_id") }
            let payment = paymentRecords.first {
                $0.values.text("training_student_id") == session.values.text("student_id")
                    && $0.values.text("week_date").hasPrefix(session.values.text("session_date").prefix(10))
            }
            let amount = payment?.values.number("amount")
                ?? student?.values.number("payment_amount", fallback: 80)
                ?? 80
            var values = session.values
            values.merge([
                "id": .string("session-\(session.id)"),
                "session_id": .string(session.id),
                "source_student_id": .string(session.values.text("student_id")),
                "student_name": .string(student?.values.text("student_name", fallback: "Missing student") ?? "Missing student"),
                "coach_name": .string(session.values.text("coach_name", fallback: session.values.text("coach_id", fallback: "Unassigned"))),
                "training_status": .string(session.values.flag("removed_from_training") ? "Removed from attendance" : "Active"),
                "amount": .number(amount),
                "paid": .bool(payment?.values.flag("paid") ?? false),
                "payment_id": .string(payment?.id ?? "")
            ]) { _, new in new }
            return DynamicRecord(values: values)
        }
    }

    private func loadMonthlyCounterResetAt(
        programme: Programme,
        month: Date
    ) async throws -> Date? {
        let programmeKey = programme == .oneToOne
            ? "one_to_one"
            : programme.rawValue
        let records = try await BackendClient.shared.select(
            table: "payment_counter_state",
            query: [
                .init(name: "programme", value: "eq.\(programmeKey)"),
                .init(name: "period_key", value: "eq.\(month.monthKey)"),
                .init(name: "limit", value: "1")
            ]
        )
        return records.first.flatMap {
            parseISODate($0.values.text("reset_at"))
        }
    }

    private func paymentTimestamp(_ payment: DynamicRecord) -> Date? {
        parseISODate(
            payment.values.text(
                "updated_at",
                fallback: payment.values.text("created_at")
            )
        )
    }

    private func setPaid(_ row: DynamicRecord, paid: Bool) async {
        let activity = state.beginActivity(
            paid ? "Recording payment and notifying Telegram…" : "Reversing payment and notifying Telegram…"
        )
        defer { state.endActivity(activity) }
        pendingToggle = nil
        do {
            switch programme {
            case .weekend:
                try await setWeekendPaid(row, paid: paid)
            case .weekday:
                try await setWeekdayPaid(row, paid: paid)
            case .matchplay:
                try await setMatchPlayPaid(row, paid: paid)
            case .oneToOne:
                try await setOneToOnePaid(row, paid: paid)
            }
            state.show("\(row.values.text("student_name", fallback: "Student")) marked \(paid ? "paid" : "unpaid").")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
            await load()
        }
    }

    private func studentForAdjustment(_ row: DynamicRecord) -> DynamicRecord? {
        students.first { $0.id == row.values.text("source_student_id") }
    }

    private func saveAdjustment(
        _ adjustment: PaymentAdjustment,
        for row: DynamicRecord
    ) async {
        let activity = state.beginActivity("Saving payment details…")
        defer { state.endActivity(activity) }
        do {
            let now = ISO8601DateFormatter().string(from: Date())
            switch programme {
            case .weekend:
                break
            case .weekday:
                guard let student = studentForAdjustment(row) else {
                    throw BackendError.message("Weekday student not found.")
                }
                let rate = student.values.number("hourly_rate", fallback: 80)
                for day in adjustment.weekdayDays {
                    let existing = paymentRecords.first {
                        $0.values.text("weekday_student_id") == student.id
                            && $0.values.text("day_name") == day.day
                    }
                    let scheduled = day.scheduledHours
                    let payable = day.manualHours ?? scheduled
                    _ = try await BackendClient.shared.upsert(
                        table: "weekday_payments",
                        values: [
                            "weekday_student_id": .string(student.id),
                            "payment_month": .string(month.monthKey),
                            "day_name": .string(day.day),
                            "paid": .bool(existing?.values.flag("paid") ?? false),
                            "scheduled_hours": .number(scheduled),
                            "manual_hours": day.manualHours.map(JSONValue.number) ?? .null,
                            "amount": .number(payable * rate),
                            "updated_at": .string(now)
                        ],
                        onConflict: "weekday_student_id,payment_month,day_name"
                    )
                }
            case .matchplay:
                let sourceStudent = studentForAdjustment(row)
                let weeks = adjustment.weeks
                    ?? sourceStudent?.values.number("number_of_weeks")
                    ?? row.values.number("weeks")
                let rate = adjustment.rate
                    ?? sourceStudent?.values.number("price_per_session")
                    ?? row.values.number("price_per_session")
                _ = try await BackendClient.shared.upsert(
                    table: "matchplay_payments",
                    values: [
                        "matchplay_student_id": .string(row.values.text("source_student_id")),
                        "payment_month": .string(month.monthKey),
                        "paid": .bool(isPaid(row)),
                        "manual_weeks": adjustment.weeks.map(JSONValue.number) ?? .null,
                        "manual_price_per_session": adjustment.rate.map(JSONValue.number) ?? .null,
                        "amount": .number(weeks * rate),
                        "updated_at": .string(now)
                    ],
                    onConflict: "matchplay_student_id,payment_month"
                )
            case .oneToOne:
                guard let amount = adjustment.amount, amount >= 0 else {
                    throw BackendError.message("Enter a valid payment amount.")
                }
                _ = try await BackendClient.shared.upsert(
                    table: "training_payments",
                    values: [
                        "training_student_id": .string(row.values.text("source_student_id")),
                        "week_date": .string(String(row.values.text("session_date").prefix(10))),
                        "paid": .bool(isPaid(row)),
                        "amount": .number(amount),
                        "updated_at": .string(now)
                    ],
                    onConflict: "training_student_id,week_date"
                )
            }
            adjustingRow = nil
            state.show("Payment details updated.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func setWeekendPaid(_ row: DynamicRecord, paid: Bool) async throws {
        let studentID = row.values.text("student_id", fallback: row.values.text("id"))
        let now = ISO8601DateFormatter().string(from: Date())
        let amount = row.values.number("amount")
        _ = try await BackendClient.shared.update(
            table: "students",
            values: ["paid": .bool(paid), "updated_at": .string(now)],
            filters: [.init(name: "student_id", value: "eq.\(studentID)")]
        )
        _ = try await BackendClient.shared.websiteData(
            path: PaymentWebsiteRoute.ensureWeekendHistory,
            method: PaymentWebsiteRoute.ensureWeekendHistoryMethod
        )
        _ = try await BackendClient.shared.insert(
            table: "payment_history",
            values: [
                "student_id": .string(studentID),
                "amount": .number(paid ? amount : -amount),
                "recorded_at": .string(now)
            ]
        )
        let message = """
        \(paid ? "✅ Weekend Payment Received" : "↩️ Weekend Payment Reversed")

        Student: \(row.values.text("student_name"))
        Amount: \(paid ? "+" : "-")\(amount.formatted(.currency(code: "SGD")))
        Recorded At: \(Date().formatted())
        Status: \(paid ? "Paid" : "Unpaid")
        """
        try await telegram(path: "/api/telegram-weekend-payment", message: message)
    }

    private func setWeekdayPaid(_ row: DynamicRecord, paid: Bool) async throws {
        let studentID = row.values.text("source_student_id")
        guard let student = students.first(where: { $0.id == studentID }) else {
            throw BackendError.message("Weekday student not found.")
        }
        let schedules = student.values["schedules"]?.array?.compactMap(\.object) ?? []
        let rate = student.values.number("hourly_rate", fallback: 80)
        let now = ISO8601DateFormatter().string(from: Date())

        for schedule in schedules {
            let day = schedule.text("day")
            let duration = schedule.number("duration_hours", fallback: 1)
            let scheduledHours = duration * Double(weekdayOccurrences(day: day, month: month))
            let existing = paymentRecords.first {
                $0.values.text("weekday_student_id") == studentID
                    && $0.values.text("day_name") == day
            }
            let hours = existing?.values["manual_hours"]?.double ?? scheduledHours
            _ = try await BackendClient.shared.upsert(
                table: "weekday_payments",
                values: [
                    "weekday_student_id": .string(studentID),
                    "payment_month": .string(month.monthKey),
                    "day_name": .string(day),
                    "paid": .bool(paid),
                    "scheduled_hours": .number(scheduledHours),
                    "manual_hours": existing?.values["manual_hours"] ?? .null,
                    "amount": .number(hours * rate),
                    "updated_at": .string(now)
                ],
                onConflict: "weekday_student_id,payment_month,day_name"
            )
        }

        let message = """
        \(paid ? "✅ Weekday Payment Received!" : "↩️ Weekday Payment Reversed!")

        Student: \(row.values.text("student_name"))
        Month: \(month.formatted(.dateTime.month(.wide).year()))
        Days: \(row.values.text("days"))
        Sessions: \(Int(row.values.number("sessions")))
        Payable Hours: \(row.values.number("payable_hours"))h
        Amount: \(paid ? "+" : "-")\(row.values.number("amount").formatted(.currency(code: "SGD")))
        Recorded At: \(Date().formatted())
        Status: \(paid ? "Paid" : "Unpaid")
        """
        try await telegram(path: "/api/telegram-weekday-payment", message: message)
    }

    private func setMatchPlayPaid(_ row: DynamicRecord, paid: Bool) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        _ = try await BackendClient.shared.upsert(
            table: "matchplay_payments",
            values: [
                "matchplay_student_id": .string(row.values.text("source_student_id")),
                "payment_month": .string(month.monthKey),
                "paid": .bool(paid),
                "manual_weeks": .number(row.values.number("weeks")),
                "manual_price_per_session": .number(row.values.number("price_per_session")),
                "amount": .number(row.values.number("amount")),
                "updated_at": .string(now)
            ],
            onConflict: "matchplay_student_id,payment_month"
        )
        let message = """
        \(paid ? "✅ MatchPlay Payment Received!" : "↩️ MatchPlay Payment Reversed!")

        Student: \(row.values.text("student_name"))
        Month: \(month.formatted(.dateTime.month(.wide).year()))
        Weeks: \(Int(row.values.number("weeks")))
        Price Per Session: \(row.values.number("price_per_session").formatted(.currency(code: "SGD")))
        Amount: \(paid ? "+" : "-")\(row.values.number("amount").formatted(.currency(code: "SGD")))
        Recorded At: \(Date().formatted())
        Status: \(paid ? "Paid" : "Unpaid")
        """
        try await telegram(path: "/api/telegram-matchplay-payment", message: message)
    }

    private func setOneToOnePaid(_ row: DynamicRecord, paid: Bool) async throws {
        let now = ISO8601DateFormatter().string(from: Date())
        let dateKey = String(row.values.text("session_date").prefix(10))
        _ = try await BackendClient.shared.upsert(
            table: "training_payments",
            values: [
                "training_student_id": .string(row.values.text("source_student_id")),
                "week_date": .string(dateKey),
                "paid": .bool(paid),
                "amount": .number(row.values.number("amount")),
                "updated_at": .string(now)
            ],
            onConflict: "training_student_id,week_date"
        )
        let message = """
        \(paid ? "✅ 1-on-1 Payment Received!" : "↩️ 1-on-1 Payment Reversed!")

        Student: \(row.values.text("student_name"))
        Coach: \(row.values.text("coach_name"))
        Session Date: \(dateKey)
        Amount: \(paid ? "+" : "-")\(row.values.number("amount").formatted(.currency(code: "SGD")))
        Recorded At: \(Date().formatted())
        Status: \(paid ? "Paid" : "Unpaid")
        """
        try await telegram(path: "/api/telegram-trngpayment", message: message)
    }

    private func telegram(path: String, message: String) async throws {
        _ = try await BackendClient.shared.websiteJSON(
            path: path,
            method: "POST",
            body: ["message": .string(message)]
        )
    }

    private func undoLatest() async {
        let activity = state.beginActivity("Undoing latest payment and notifying Telegram…")
        defer { state.endActivity(activity) }
        do {
            switch programme {
            case .weekend:
                guard let payment = paymentRecords.first else {
                    throw BackendError.message("There is no Weekend payment to undo.")
                }
                let studentID = payment.values.text("student_id")
                _ = try await BackendClient.shared.update(
                    table: "students",
                    values: ["paid": .bool(false)],
                    filters: [.init(name: "student_id", value: "eq.\(studentID)")]
                )
                try await BackendClient.shared.delete(
                    table: "payment_history",
                    filters: [.init(name: "recorded_at", value: "eq.\(payment.values.text("recorded_at"))")]
                )
                let student = students.first { $0.values.text("student_id") == studentID }
                let message = """
                ↩️ Payment Undone ↩️

                Student: \(student?.values.text("student_name", fallback: "Unknown") ?? "Unknown")
                Amount: \(abs(payment.values.number("amount")).formatted(.currency(code: "SGD")))
                Recorded at: \(payment.values.text("recorded_at"))
                Status: Marked as unpaid
                """
                try await telegram(path: "/api/telegram-weekend-payment", message: message)
            case .weekday:
                guard let payment = newestPaidRecord else { throw BackendError.message("No paid Weekday payment found.") }
                guard let row = rows.first(where: { $0.values.text("source_student_id") == payment.values.text("weekday_student_id") }) else { throw BackendError.message("Student not found.") }
                try await setWeekdayPaid(row, paid: false)
            case .matchplay:
                guard let payment = newestPaidRecord else { throw BackendError.message("No paid MatchPlay payment found.") }
                guard let row = rows.first(where: { $0.values.text("source_student_id") == payment.values.text("matchplay_student_id") }) else { throw BackendError.message("Student not found.") }
                try await setMatchPlayPaid(row, paid: false)
            case .oneToOne:
                guard let payment = newestPaidRecord else { throw BackendError.message("No paid 1-1 payment found.") }
                guard let row = rows.first(where: {
                    $0.values.text("source_student_id") == payment.values.text("training_student_id")
                        && $0.values.text("session_date").hasPrefix(payment.values.text("week_date").prefix(10))
                }) else { throw BackendError.message("Session not found.") }
                try await setOneToOnePaid(row, paid: false)
            }
            state.show("Latest payment undone and Telegram notified.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private var newestPaidRecord: DynamicRecord? {
        paymentRecords.filter { $0.values.flag("paid") }.max {
            $0.values.text("updated_at", fallback: $0.values.text("created_at"))
                < $1.values.text("updated_at", fallback: $1.values.text("created_at"))
        }
    }

    private func resetDisplayedTotal() async {
        let activity = state.beginActivity("Sending payment summary and resetting the displayed total…")
        defer { state.endActivity(activity) }
        do {
            let name = programme == .oneToOne ? "1-on-1" : programme.title
            let details: String
            if programme == .weekend {
                details = paymentRecords.map { payment in
                    let studentID = payment.values.text("student_id")
                    let studentName = students.first {
                        $0.values.text("student_id", fallback: $0.id) == studentID
                    }?.values.text("student_name", fallback: "Unknown student")
                        ?? "Unknown student"
                    let amount = payment.values.number("amount")
                    let sign = amount >= 0 ? "+" : "-"
                    let recorded = parseISODate(payment.values.text("recorded_at"))?
                        .formatted(.dateTime.day().month(.abbreviated).year())
                        ?? payment.values.text("recorded_at")
                    return "- \(studentName): \(sign)\(abs(amount).formatted(.currency(code: "SGD"))) (\(recorded))"
                }.joined(separator: "\n")
            } else {
                details = rows.map { row in
                    "- \(row.values.text("student_name")): \(row.values.number("amount").formatted(.currency(code: "SGD"))) (\(isPaid(row) ? "Paid" : "Unpaid"))"
                }.joined(separator: "\n")
            }
            let message = """
            📊 \(name) Payment Summary 📊

            Period: \(programme == .weekend ? weekendQuarterLabel : month.formatted(.dateTime.month(.wide).year()))
            Total Collected: \(fullPeriodCollected.formatted(.currency(code: "SGD")))
            Possible Total: \(possible.formatted(.currency(code: "SGD")))
            Paid: \(paidRows.count)
            Unpaid: \(rows.count - paidRows.count)

            Payment Details:
            \(details.isEmpty ? "- No payment records." : details)

            Reset triggered at: \(Date().formatted())
            """
            let endpoint: String
            switch programme {
            case .weekend: endpoint = "/api/telegram-weekend-payment"
            case .weekday: endpoint = "/api/telegram-weekday-payment"
            case .matchplay: endpoint = "/api/telegram-matchplay-payment"
            case .oneToOne: endpoint = "/api/telegram-trngpayment"
            }
            try await telegram(path: endpoint, message: message)

            let now = isoString(Date())
            if programme == .weekend {
                let period = WeekendPaymentQuarter.new(startingAt: Date())
                _ = try await BackendClient.shared.upsert(
                    table: "weekend_payment_period_state",
                    values: [
                        "id": .number(1),
                        "start_at": .string(isoString(period.start)),
                        "end_at": .string(isoString(period.end)),
                        "updated_at": .string(now)
                    ],
                    onConflict: "id"
                )
            } else {
                _ = try await BackendClient.shared.upsert(
                    table: "payment_counter_state",
                    values: [
                        "programme": .string(programme == .oneToOne ? "one_to_one" : programme.rawValue),
                        "period_key": .string(month.monthKey),
                        "reset_at": .string(now),
                        "reset_by": state.user.map { .string($0.id) } ?? .null,
                        "updated_at": .string(now)
                    ],
                    onConflict: "programme,period_key"
                )
            }
            state.show("Summary sent. Displayed counter reset; payment statuses were preserved.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func weekdayOccurrences(day: String, month: Date) -> Int {
        let weekdayMap = ["Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7]
        guard let target = weekdayMap[day],
              let interval = Calendar.current.dateInterval(of: .month, for: month) else {
            return 0
        }
        var count = 0
        var current = interval.start
        while current < interval.end {
            if Calendar.current.component(.weekday, from: current) == target { count += 1 }
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? interval.end
        }
        return count
    }

    private func nextMonthKey(_ date: Date) -> String {
        Calendar.current.date(byAdding: .month, value: 1, to: date)?.monthKey ?? date.monthKey
    }

    private func isoString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private func changeMonth(by value: Int) {
        month = Calendar.current.date(byAdding: .month, value: value, to: month) ?? month
    }
}

private struct PaymentDayAdjustment: Identifiable, Sendable {
    let day: String
    let scheduledHours: Double
    let manualHours: Double?

    var id: String { day }
}

private struct PaymentAdjustment: Sendable {
    var weekdayDays: [PaymentDayAdjustment] = []
    var weeks: Double?
    var rate: Double?
    var amount: Double?
}

private struct PaymentAdjustmentSheet: View {
    @Environment(\.dismiss) private var dismiss

    let programme: Programme
    let row: DynamicRecord
    let student: DynamicRecord?
    let paymentRecords: [DynamicRecord]
    let month: Date
    let onSave: (PaymentAdjustment) async -> Void

    @State private var weekdayInputs: [String: String]
    @State private var weeks: String
    @State private var rate: String
    @State private var amount: String
    @State private var useStudentDefaults: Bool

    init(
        programme: Programme,
        row: DynamicRecord,
        student: DynamicRecord?,
        paymentRecords: [DynamicRecord],
        month: Date,
        onSave: @escaping (PaymentAdjustment) async -> Void
    ) {
        self.programme = programme
        self.row = row
        self.student = student
        self.paymentRecords = paymentRecords
        self.month = month
        self.onSave = onSave

        var dayInputs: [String: String] = [:]
        if let student {
            for schedule in student.values["schedules"]?.array?.compactMap(\.object) ?? [] {
                let day = schedule.text("day")
                let existing = paymentRecords.first {
                    $0.values.text("weekday_student_id") == student.id
                        && $0.values.text("day_name") == day
                }
                if let manual = existing?.values["manual_hours"]?.double {
                    dayInputs[day] = Self.numberString(manual)
                } else {
                    let duration = schedule.number("duration_hours", fallback: 1)
                    dayInputs[day] = Self.numberString(
                        duration * Double(Self.weekdayOccurrences(day: day, month: month))
                    )
                }
            }
        }
        _weekdayInputs = State(initialValue: dayInputs)

        let existingMatchPlay = paymentRecords.first {
            $0.values.text("matchplay_student_id") == row.values.text("source_student_id")
        }
        let usesDefaults = existingMatchPlay?.values["manual_weeks"]?.double == nil
            && existingMatchPlay?.values["manual_price_per_session"]?.double == nil
        _useStudentDefaults = State(initialValue: usesDefaults)
        _weeks = State(initialValue: Self.numberString(row.values.number("weeks")))
        _rate = State(initialValue: Self.numberString(row.values.number("price_per_session")))
        _amount = State(initialValue: Self.numberString(row.values.number("amount")))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(title: "Adjust Payment", onCancel: { dismiss() })

                Form {
                    Section("Student") {
                        LabeledContent("Name", value: row.values.text("student_name", fallback: "Student"))
                        LabeledContent("Period", value: month.formatted(.dateTime.month(.wide).year()))
                    }

                    switch programme {
                    case .weekday:
                        weekdayFields
                    case .matchplay:
                        matchPlayFields
                    case .oneToOne:
                        Section("Session payment") {
                            TextField("Amount", text: $amount)
                                .keyboardType(.decimalPad)
                            Text("This changes the payment amount for this specific session.")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    case .weekend:
                        EmptyView()
                    }

                    Section {
                        AsyncActionButton(
                            title: "Save Adjustment",
                            progressTitle: "Saving adjustment…",
                            icon: "checkmark.circle.fill",
                            disabled: !isValid
                        ) {
                            await save()
                        }
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var weekdayFields: some View {
        Section("Payable hours") {
            ForEach(weekdaySchedules, id: \.day) { schedule in
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(schedule.day)
                                .font(.body.weight(.semibold))
                            Text("Calculated schedule: \(Self.numberString(schedule.scheduledHours)) hours")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        TextField(
                            "Payable hours",
                            text: Binding(
                                get: { weekdayInputs[schedule.day] ?? "" },
                                set: { weekdayInputs[schedule.day] = $0 }
                            )
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(Color(uiColor: .systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Theme.border, lineWidth: 1)
                        )
                        .frame(width: 92)
                    }
                    Button("Use calculated hours") {
                        weekdayInputs[schedule.day] = Self.numberString(schedule.scheduledHours)
                    }
                    .buttonStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                }
            }
            Text("Tap each number to edit its payable hours. Matching the calculated value restores the automatic schedule amount.")
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
        }
    }

    @ViewBuilder
    private var matchPlayFields: some View {
        Section("Monthly calculation") {
            Toggle("Use student defaults", isOn: $useStudentDefaults)
            TextField("Weeks", text: $weeks)
                .keyboardType(.decimalPad)
                .disabled(useStudentDefaults)
            TextField("Price per session", text: $rate)
                .keyboardType(.decimalPad)
                .disabled(useStudentDefaults)
            if let weeksValue = Double(weeks), let rateValue = Double(rate) {
                LabeledContent("Calculated amount") {
                    Text(weeksValue * rateValue, format: .currency(code: "SGD"))
                }
            }
        }
    }

    private var weekdaySchedules: [PaymentDayAdjustment] {
        guard let student else { return [] }
        return (student.values["schedules"]?.array?.compactMap(\.object) ?? []).map { schedule in
            let day = schedule.text("day")
            let duration = schedule.number("duration_hours", fallback: 1)
            return PaymentDayAdjustment(
                day: day,
                scheduledHours: duration * Double(Self.weekdayOccurrences(day: day, month: month)),
                manualHours: nil
            )
        }
    }

    private var isValid: Bool {
        switch programme {
        case .weekday:
            return weekdaySchedules.allSatisfy {
                (Double(weekdayInputs[$0.day] ?? "") ?? -1) >= 0
            }
        case .matchplay:
            return useStudentDefaults
                || ((Double(weeks) ?? -1) >= 0 && (Double(rate) ?? -1) >= 0)
        case .oneToOne:
            return (Double(amount) ?? -1) >= 0
        case .weekend:
            return false
        }
    }

    private func save() async {
        var adjustment = PaymentAdjustment()
        switch programme {
        case .weekday:
            adjustment.weekdayDays = weekdaySchedules.map { schedule in
                let enteredHours = Double(weekdayInputs[schedule.day] ?? "")
                return PaymentDayAdjustment(
                    day: schedule.day,
                    scheduledHours: schedule.scheduledHours,
                    manualHours: enteredHours.map {
                        abs($0 - schedule.scheduledHours) < 0.0001 ? nil : $0
                    } ?? nil
                )
            }
        case .matchplay:
            if !useStudentDefaults {
                adjustment.weeks = Double(weeks)
                adjustment.rate = Double(rate)
            }
        case .oneToOne:
            adjustment.amount = Double(amount)
        case .weekend:
            return
        }
        await onSave(adjustment)
        dismiss()
    }

    private static func numberString(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(value)
    }

    private static func weekdayOccurrences(day: String, month: Date) -> Int {
        let map = ["Sunday": 1, "Monday": 2, "Tuesday": 3, "Wednesday": 4, "Thursday": 5, "Friday": 6, "Saturday": 7]
        guard let target = map[day],
              let interval = Calendar.current.dateInterval(of: .month, for: month) else {
            return 0
        }
        var result = 0
        var current = interval.start
        while current < interval.end {
            if Calendar.current.component(.weekday, from: current) == target {
                result += 1
            }
            current = Calendar.current.date(byAdding: .day, value: 1, to: current) ?? interval.end
        }
        return result
    }
}
