import Foundation
import SwiftUI

enum AttendanceReportScope: Equatable {
    case mine
    case all
}

enum AttendanceRecordView: String, CaseIterable, Identifiable {
    case specificDate
    case allRecords

    var id: Self { self }

    var title: String {
        switch self {
        case .specificDate: "Specific Date"
        case .allRecords: "All Records"
        }
    }

    func includes(dateKey: String, selectedDateKey: String) -> Bool {
        switch self {
        case .allRecords:
            true
        case .specificDate:
            AttendanceDateKey.dateOnly(from: dateKey) == selectedDateKey
        }
    }
}

enum AttendanceDateKey {
    /// Normalises the formats already used by the website and Telegram poll
    /// history: ISO, ISO with a shift suffix, pipe-delimited ISO, and d/M/yyyy.
    static func dateOnly(from rawValue: String) -> String? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.count >= 10 {
            let prefix = String(value.prefix(10))
            let characters = Array(prefix)
            if characters.count == 10,
               characters[4] == "-",
               characters[7] == "-",
               Int(prefix.prefix(4)) != nil,
               Int(prefix.dropFirst(5).prefix(2)) != nil,
               Int(prefix.suffix(2)) != nil,
               isValidISODate(prefix) {
                return prefix
            }
        }

        let slashDate = value
            .split(separator: "|", maxSplits: 1)
            .first?
            .split(separator: "-", maxSplits: 1)
            .first?
            .split(separator: "/")

        guard let slashDate,
              slashDate.count == 3,
              let day = Int(slashDate[0]),
              let month = Int(slashDate[1]),
              let year = Int(slashDate[2]),
              (1...31).contains(day),
              (1...12).contains(month) else {
            return nil
        }

        let normalized = String(format: "%04d-%02d-%02d", year, month, day)
        return isValidISODate(normalized) ? normalized : nil
    }

    private static func isValidISODate(_ value: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value) != nil
    }
}

enum CoachingAttendancePay {
    static let oneToOneAmount = 40.0
    static let fullShiftAmount = 70.0
    static let hourlyAmount = 17.5

    static func amount(source: String, dateKey: String) -> Double? {
        if source == "one_to_one" { return oneToOneAmount }
        return telegramAmount(dateKey: dateKey)
    }

    static func telegramAmount(dateKey: String) -> Double? {
        guard let weekday = weekday(for: dateKey) else { return nil }

        guard let hours = slotHours(from: dateKey) else {
            // Saturday coach polls historically store one date-only option
            // representing the complete Weekend coaching shift.
            return weekday == 7 ? fullShiftAmount : nil
        }

        let standardSaturdaySlot = weekday == 7
            && (hours == (2, 4) || hours == (4, 6))
        let standardSundaySlot = weekday == 1
            && (hours == (8, 12) || hours == (1, 5))

        if standardSaturdaySlot || standardSundaySlot {
            return fullShiftAmount
        }

        guard let duration = durationHours(start: hours.start, end: hours.end) else {
            return nil
        }
        return Double(duration) * hourlyAmount
    }

    static func slotHours(from rawValue: String) -> (start: Int, end: Int)? {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)

        let pipeParts = value.split(separator: "|", omittingEmptySubsequences: true)
        if pipeParts.count >= 3,
           let start = leadingHour(in: String(pipeParts[pipeParts.count - 2])),
           let end = leadingHour(in: String(pipeParts[pipeParts.count - 1])) {
            return (start, end)
        }

        guard AttendanceDateKey.dateOnly(from: value) != nil else { return nil }
        let suffixParts: [Substring]
        if value.count >= 10,
           String(value.prefix(10)).split(separator: "-").count == 3 {
            suffixParts = value.dropFirst(10).split(separator: "-")
        } else {
            suffixParts = value.split(separator: "-").dropFirst().map { $0 }
        }

        guard suffixParts.count >= 2,
              let start = leadingHour(in: String(suffixParts[suffixParts.count - 2])),
              let end = leadingHour(in: String(suffixParts[suffixParts.count - 1])) else {
            return nil
        }
        return (start, end)
    }

    static func formatted(_ amount: Double) -> String {
        String(format: "S$%.2f", amount)
    }

    private static func leadingHour(in value: String) -> Int? {
        let digits = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix { $0.isNumber }
        guard let hour = Int(digits), (1...12).contains(hour) else { return nil }
        return hour
    }

    private static func durationHours(start: Int, end: Int) -> Int? {
        let duration: Int
        if start == 12, end <= 6 {
            duration = end
        } else if end > start {
            duration = end - start
        } else {
            duration = end + 12 - start
        }
        return (1...12).contains(duration) ? duration : nil
    }

    private static func weekday(for dateKey: String) -> Int? {
        guard let normalized = AttendanceDateKey.dateOnly(from: dateKey) else {
            return nil
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: normalized) else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar.component(.weekday, from: date)
    }
}

struct ReportsView: View {
    @EnvironmentObject private var state: AppState

    @State private var records: [DynamicRecord] = []
    @State private var recordView: AttendanceRecordView = .specificDate
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var isDatePickerPresented = false
    @State private var search = ""
    @State private var loading = false
    @State private var activeLoadID: UUID?

    let scope: AttendanceReportScope

    init(scope: AttendanceReportScope = .mine) {
        self.scope = scope
    }

    private var filtered: [DynamicRecord] {
        records.filter { $0.matches(search) }
    }

    private var selectedDateKey: String { selectedDate.isoDateKey }

    private var loadKey: String {
        switch recordView {
        case .specificDate: "date-\(selectedDateKey)"
        case .allRecords: "all-records"
        }
    }

    private var selectedDateLabel: String {
        selectedDate.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }

    private var estimatedPay: Double {
        filtered.reduce(0) { total, record in
            total + record.values.number("estimated_pay_value")
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                HStack {
                    Label(
                        scope == .mine ? "My coaching shifts" : "All coaching shifts",
                        systemImage: scope == .mine ? "person.crop.circle.badge.checkmark" : "person.3.sequence.fill"
                    )
                    .font(.headline)
                    Spacer()
                }

                recordFilter

                MetricCard(
                    title: "Estimated coaching pay",
                    value: CoachingAttendancePay.formatted(estimatedPay),
                    icon: "dollarsign.circle.fill",
                    color: Theme.purple
                )

                HStack(spacing: 12) {
                    MetricCard(
                        title: "Confirmed shifts",
                        value: "\(filtered.count)",
                        icon: "checkmark.seal.fill",
                        color: Theme.blue
                    )
                    MetricCard(
                        title: "1-1 sessions",
                        value: "\(filtered.filter { $0.values.text("source") == "one_to_one" }.count)",
                        icon: "person.2.fill",
                        color: Theme.green
                    )
                }

                HStack {
                    Text("\(filtered.count) attendance record\(filtered.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(
                        scope: scope == .mine ? "my coaching attendance" : "all coaching attendance"
                    ) {
                        await load()
                    }
                }

                if scope == .all {
                    AppSearchField(prompt: "Search coach or date", text: $search)
                }

                if filtered.isEmpty && !loading {
                    EmptyState(
                        icon: "chart.bar",
                        title: "No coaching attendance",
                        message: emptyMessage
                    )
                }

                ForEach(groupedDates, id: \.date) { group in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(displayDate(group.date))
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        ForEach(group.items) { record in
                            RecordCard(
                                record: record,
                                titleKeys: scope == .mine ? ["time_label", "status_label"] : ["coach_name"],
                                detailKeys: scope == .mine
                                    ? ["status_label", "estimated_pay", "source_label"]
                                    : ["time_label", "status_label", "estimated_pay", "source_label"],
                                query: search,
                                status: record.values.text("status_label")
                            )
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle(scope == .mine ? "My Attendance" : "All Attendance")
        .task(id: loadKey) { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $isDatePickerPresented) {
            AttendanceDatePickerSheet(selectedDate: selectedDate) { date in
                selectedDate = Calendar.current.startOfDay(for: date)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .overlay { if loading { LoadingOverlay(text: loadingMessage) } }
    }

    private var recordFilter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Attendance records", systemImage: "line.3.horizontal.decrease.circle")
                .font(.headline)
                .foregroundStyle(Theme.ink)

            Picker("Record view", selection: $recordView) {
                ForEach(AttendanceRecordView.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("attendance-record-filter")

            if recordView == .specificDate {
                Button {
                    isDatePickerPresented = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.headline)
                            .foregroundStyle(Theme.blue)
                            .frame(width: 34, height: 34)
                            .background(Theme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 9))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Calendar day")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                            Text(selectedDateLabel)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.ink)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(minHeight: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Choose attendance date")
                .accessibilityValue(selectedDateLabel)
                .accessibilityIdentifier("attendance-date-button")

                Text("Selecting a date closes the calendar and reloads only that day's shifts.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Showing every available coaching attendance record.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .appCard()
    }

    private var emptyMessage: String {
        switch recordView {
        case .specificDate:
            "No confirmed Telegram shifts or assigned 1-1 sessions exist on \(selectedDateLabel)."
        case .allRecords:
            "No confirmed Telegram shifts or assigned 1-1 sessions are available."
        }
    }

    private var loadingMessage: String {
        switch recordView {
        case .specificDate: "Checking shifts for \(selectedDateLabel)"
        case .allRecords: "Loading all coaching attendance"
        }
    }

    private var groupedDates: [(date: String, items: [DynamicRecord])] {
        let grouped = Dictionary(grouping: filtered) { record in
            AttendanceDateKey.dateOnly(from: record.values.text("date_key"))
                ?? record.values.text("date_key")
        }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    private func load() async {
        let requestedView = recordView
        let requestedDateKey = selectedDateKey
        let loadID = UUID()
        activeLoadID = loadID
        loading = true
        defer {
            if activeLoadID == loadID {
                loading = false
            }
        }

        do {
            let myID = state.user?.id ?? ""
            let profiles = try await loadProfiles(myID: myID)
            let myHandle = profiles.first { $0.values.text("auth_user_id") == myID }
                .map { normalizedHandle($0.values.text("telegram_handle")) } ?? ""

            async let loadedVotes = loadVotes(myHandle: myHandle)
            async let loadedSessions = loadSessions(
                for: requestedView,
                selectedDateKey: requestedDateKey,
                myID: myID
            )
            async let loadedUsers = loadUsers()

            let votes = try await loadedVotes
            let sessions = try await loadedSessions
            let users = try await loadedUsers
            try Task.checkCancellation()

            let names = Dictionary(uniqueKeysWithValues: users.map { ($0.id, displayName($0)) })
            let profileByHandle = profiles.reduce(into: [String: String]()) { result, profile in
                let handle = normalizedHandle(profile.values.text("telegram_handle"))
                if !handle.isEmpty {
                    result[handle] = profile.values.text("auth_user_id")
                }
            }

            let voteRows = votes.compactMap { vote -> DynamicRecord? in
                let dateKey = vote.values.text("date_key")
                guard requestedView.includes(
                    dateKey: dateKey,
                    selectedDateKey: requestedDateKey
                ) else { return nil }

                let handle = normalizedHandle(
                    vote.values.text("telegram_handle", fallback: vote.values.text("display_name"))
                )
                let ownerID = profileByHandle[handle]
                if scope == .mine && ownerID != myID && handle != myHandle { return nil }

                var values = vote.values
                values["id"] = .string("telegram-\(vote.id)")
                values["source"] = .string("telegram")
                values["source_label"] = .string("Telegram coach poll")
                values["coach_name"] = .string(ownerID.flatMap { names[$0] } ?? vote.values.text("display_name", fallback: handle.isEmpty ? "Unlinked coach" : handle))
                values["time_label"] = .string(timeLabel(dateKey))
                values["status_label"] = .string("Attending")
                if let amount = CoachingAttendancePay.amount(
                    source: "telegram",
                    dateKey: dateKey
                ) {
                    values["estimated_pay"] = .string(CoachingAttendancePay.formatted(amount))
                    values["estimated_pay_value"] = .number(amount)
                } else {
                    values["estimated_pay"] = .string("Unavailable")
                    values["estimated_pay_value"] = .number(0)
                }
                return DynamicRecord(values: values)
            }

            let sessionRows = sessions.compactMap { session -> DynamicRecord? in
                let coachID = session.values.text("coach_id")
                if scope == .mine && coachID != myID { return nil }

                let dateKey = String(session.values.text("session_date").prefix(10))
                guard requestedView.includes(
                    dateKey: dateKey,
                    selectedDateKey: requestedDateKey
                ) else { return nil }

                var values = session.values
                values["id"] = .string("one-to-one-\(session.id)")
                values["source"] = .string("one_to_one")
                values["source_label"] = .string("1-1 coaching")
                values["date_key"] = .string(dateKey)
                values["coach_name"] = .string(names[coachID] ?? "Unassigned coach")
                values["time_label"] = .string("1-1 session")
                values["status_label"] = .string("1-1 Coaching")
                values["estimated_pay"] = .string(
                    CoachingAttendancePay.formatted(CoachingAttendancePay.oneToOneAmount)
                )
                values["estimated_pay_value"] = .number(
                    CoachingAttendancePay.oneToOneAmount
                )
                return DynamicRecord(values: values)
            }

            guard activeLoadID == loadID,
                  recordView == requestedView,
                  requestedView == .allRecords || selectedDateKey == requestedDateKey else {
                return
            }

            records = (voteRows + sessionRows).sorted {
                $0.values.text("date_key") < $1.values.text("date_key")
            }
        } catch is CancellationError {
            return
        } catch {
            guard activeLoadID == loadID,
                  recordView == requestedView,
                  requestedView == .allRecords || selectedDateKey == requestedDateKey else {
                return
            }
            state.show(error)
        }
    }

    private func loadSessions(
        for requestedView: AttendanceRecordView,
        selectedDateKey: String,
        myID: String
    ) async throws -> [DynamicRecord] {
        var query = [
            URLQueryItem(
                name: "or",
                value: "(removed_from_training.is.null,removed_from_training.eq.false)"
            )
        ]

        if requestedView == .specificDate {
            query.append(.init(name: "session_date", value: "gte.\(selectedDateKey)"))
            query.append(
                .init(
                    name: "session_date",
                    value: "lt.\(nextDateKey(after: selectedDateKey))"
                )
            )
        }

        if scope == .mine {
            guard !myID.isEmpty else { return [] }
            query.append(.init(name: "coach_id", value: "eq.\(myID)"))
        }

        query.append(.init(name: "order", value: "session_date.asc"))
        return try await BackendClient.shared.select(
            table: "one_to_one_sessions",
            query: query
        )
    }

    private func loadProfiles(myID: String) async throws -> [DynamicRecord] {
        if scope == .mine {
            guard !myID.isEmpty else { return [] }
            return try await BackendClient.shared.select(
                table: "coach_profiles",
                query: [.init(name: "auth_user_id", value: "eq.\(myID)")]
            )
        }
        return try await BackendClient.shared.select(table: "coach_profiles")
    }

    private func loadVotes(myHandle: String) async throws -> [DynamicRecord] {
        var query = [
            URLQueryItem(name: "response", value: "eq.yes"),
            URLQueryItem(name: "order", value: "updated_at.asc")
        ]

        if scope == .mine {
            guard !myHandle.isEmpty else { return [] }
            query.insert(
                .init(
                    name: "or",
                    value: "(telegram_handle.ilike.@\(myHandle),telegram_handle.ilike.\(myHandle))"
                ),
                at: 1
            )
        }

        return try await BackendClient.shared.select(
            table: "coach_attendance_votes",
            query: query
        )
    }

    private func loadUsers() async throws -> [DynamicRecord] {
        guard scope == .all else { return [] }
        let response = try await BackendClient.shared.websiteJSON(path: "/api/users/list")
        return response.object?["users"]?.array?
            .compactMap(\.object)
            .map(DynamicRecord.init) ?? []
    }

    private func nextDateKey(after dateKey: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateKey),
              let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date) else {
            return dateKey
        }
        return nextDate.isoDateKey
    }

    private func displayDate(_ dateKey: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = .current
        parser.dateFormat = "yyyy-MM-dd"

        guard let date = parser.date(from: dateKey) else { return dateKey }
        return date.formatted(
            .dateTime
                .weekday(.wide)
                .day()
                .month(.wide)
                .year()
        )
    }

    private func displayName(_ user: DynamicRecord) -> String {
        user.values["user_metadata"]?.object?.text(
            "name",
            fallback: user.values.text("email", fallback: "Coach")
        ) ?? user.values.text("email", fallback: "Coach")
    }

    private func normalizedHandle(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "@", with: "")
    }

    private func timeLabel(_ dateKey: String) -> String {
        if let hours = CoachingAttendancePay.slotHours(from: dateKey) {
            return "\(hours.start)–\(hours.end)pm"
        }
        return "Saturday coaching shift"
    }
}

private struct AttendanceDatePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draftDate: Date
    let onSelect: (Date) -> Void

    init(selectedDate: Date, onSelect: @escaping (Date) -> Void) {
        _draftDate = State(initialValue: selectedDate)
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .font(.body)
                    .foregroundStyle(Theme.blue)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("attendance-date-cancel")

                Spacer(minLength: 8)

                Text("Choose a Date")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)

                Spacer(minLength: 8)

                Text("Cancel")
                    .font(.body)
                    .hidden()
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            DatePicker(
                "Attendance date",
                selection: $draftDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal, 18)
            .accessibilityIdentifier("attendance-date-picker")
            .onChange(of: draftDate) { _, newDate in
                onSelect(newDate)
                dismiss()
            }
        }
        .background(Theme.background)
    }
}
