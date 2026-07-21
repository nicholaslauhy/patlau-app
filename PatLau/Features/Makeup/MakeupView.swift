import SwiftUI

struct MakeupView: View {
    @EnvironmentObject private var state: AppState

    @State private var credits: [DynamicRecord] = []
    @State private var usages: [DynamicRecord] = []
    @State private var search = ""
    @State private var selectedSection = MakeupTrackerSection.available
    @State private var programmeFilter = "All programmes"
    @State private var loading = false
    @State private var pendingVoid: DynamicRecord?

    private let programmeFilters = [
        "All programmes", "Weekend", "Weekday", "1-1", "MatchPlay"
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Makeup tracker", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(Theme.amber)
                    Text("Track credits created from missed lessons and see exactly where each credit was used.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .lineSpacing(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()

                HStack(spacing: 12) {
                    MetricCard(
                        title: "Available",
                        value: "\(availableCredits.count)",
                        icon: "ticket.fill",
                        color: Theme.green
                    )
                    MetricCard(
                        title: "Uses recorded",
                        value: "\(usages.count)",
                        icon: "arrow.triangle.2.circlepath",
                        color: Theme.blue
                    )
                }

                HStack {
                    Text(makeupRecordCountLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(scope: "makeup tracker") { await load() }
                }

                if outstandingTopUps > 0 {
                    Label(
                        "\(outstandingTopUps) makeup top-up\(outstandingTopUps == 1 ? "" : "s") may still need payment.",
                        systemImage: "dollarsign.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                }

                Picker("Makeup records", selection: $selectedSection) {
                    ForEach(MakeupTrackerSection.allCases) { section in
                        Text(section.title).tag(section)
                    }
                }
                .pickerStyle(.segmented)

                AppSearchField(
                    prompt: "Search student, programme or status",
                    text: $search
                )

                FilterChips(values: programmeFilters, selection: $programmeFilter)

                recordsContent
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("My Makeup")
        .task { await load() }
        .refreshable { await load() }
        .alert(
            "Void Makeup Credit?",
            isPresented: Binding(
                get: { pendingVoid != nil },
                set: { if !$0 { pendingVoid = nil } }
            )
        ) {
            Button("Void Credit", role: .destructive) {
                if let credit = pendingVoid { Task { await void(credit) } }
            }
            Button("Cancel", role: .cancel) { pendingVoid = nil }
        } message: {
            Text(voidConfirmationMessage)
        }
        .overlay {
            if loading { LoadingOverlay(text: "Loading makeup records") }
        }
    }

    @ViewBuilder
    private var recordsContent: some View {
        switch selectedSection {
        case .available:
            if filteredAvailable.isEmpty && !loading {
                EmptyState(
                    icon: "ticket",
                    title: "No available credits",
                    message: "Missed lessons that qualify for makeup will appear here."
                )
            } else {
                ForEach(filteredAvailable) { credit in
                    creditCard(credit, allowsVoid: true)
                }
            }

        case .usage:
            if filteredUsages.isEmpty && !loading {
                EmptyState(
                    icon: "arrow.triangle.2.circlepath",
                    title: "No makeup usage",
                    message: "Completed makeup assignments will appear here."
                )
            } else {
                ForEach(filteredUsages) { usage in
                    usageCard(usage)
                }
            }

        case .history:
            if filteredHistory.isEmpty && !loading {
                EmptyState(
                    icon: "clock.arrow.circlepath",
                    title: "No credit history",
                    message: "Used and void credits will remain here for reference."
                )
            } else {
                ForEach(filteredHistory) { credit in
                    creditCard(credit, allowsVoid: false)
                }
            }
        }
    }

    @ViewBuilder
    private func creditCard(_ credit: DynamicRecord, allowsVoid: Bool) -> some View {
        let status = credit.values.text("status", fallback: "available")
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "ticket.fill")
                    .font(.headline)
                    .foregroundStyle(statusColour(status))
                    .frame(width: 36, height: 36)
                    .background(statusColour(status).opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(credit.values.text("student_name", fallback: "Unknown student"))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(credit.values.text("source_programme", fallback: "Makeup credit"))
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }

                Spacer(minLength: 8)
                StatusBadge(text: status, color: statusColour(status))
            }

            Divider()

            detailRow("Missed lesson", value: credit.values.text("source_label", fallback: "Not specified"))
            detailRow("Missed date", value: displayDate(credit.values.text("source_date")))
            detailRow(
                "Credit value",
                value: currency(credit.values.number("credit_value"))
            )

            if credit.values.number("credit_hours") > 0 {
                detailRow(
                    "Credit duration",
                    value: "\(formatNumber(credit.values.number("credit_hours"))) hour\(credit.values.number("credit_hours") == 1 ? "" : "s")"
                )
            }

            if allowsVoid && status == "available" {
                Divider()
                Button(role: .destructive) {
                    pendingVoid = credit
                } label: {
                    Label("Void credit", systemImage: "xmark.circle")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .appCard()
    }

    @ViewBuilder
    private func usageCard(_ usage: DynamicRecord) -> some View {
        let topUp = usage.values.number("top_up_amount")
        let paymentStatus = usage.values.text(
            "payment_status",
            fallback: topUp > 0 ? "pending" : "not required"
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.headline)
                    .foregroundStyle(Theme.blue)
                    .frame(width: 36, height: 36)
                    .background(Theme.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(usage.values.text("student_name", fallback: "Unknown student"))
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Text(usage.values.text("programme_change", fallback: "Makeup assignment"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                }

                Spacer(minLength: 8)
                StatusBadge(
                    text: paymentStatus,
                    color: paymentStatus.lowercased() == "paid" || topUp <= 0
                        ? Theme.green
                        : Theme.amber
                )
            }

            Divider()

            detailRow("Makeup date", value: displayDate(usage.values.text("target_date")))
            detailRow("Makeup lesson", value: usage.values.text("target_label", fallback: "Not specified"))
            detailRow("Target value", value: currency(usage.values.number("target_value")))
            detailRow("Credit used", value: currency(usage.values.number("credit_value_used")))

            if topUp > 0 {
                detailRow("Top-up", value: currency(topUp), colour: Theme.amber)
            }
        }
        .appCard()
    }

    private func detailRow(
        _ title: String,
        value: String,
        colour: Color = Theme.ink
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 100, alignment: .leading)
            Text(value.isEmpty ? "Not specified" : value)
                .font(.subheadline)
                .foregroundStyle(colour)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var availableCredits: [DynamicRecord] {
        credits.filter { $0.values.text("status", fallback: "available") == "available" }
    }

    private var filteredAvailable: [DynamicRecord] {
        availableCredits.filter { matchesSearch($0) && matchesProgramme($0) }
    }

    private var filteredHistory: [DynamicRecord] {
        credits.filter {
            $0.values.text("status", fallback: "available") != "available"
                && matchesSearch($0)
                && matchesProgramme($0)
        }
    }

    private var filteredUsages: [DynamicRecord] {
        usages.filter { matchesSearch($0) && matchesProgramme($0) }
    }

    private var outstandingTopUps: Int {
        usages.filter {
            $0.values.number("top_up_amount") > 0
                && $0.values.text("payment_status").lowercased() != "paid"
        }.count
    }

    private var makeupRecordCountLabel: String {
        let count: Int
        switch selectedSection {
        case .available:
            count = filteredAvailable.count
        case .usage:
            count = filteredUsages.count
        case .history:
            count = filteredHistory.count
        }
        return "\(count) makeup record\(count == 1 ? "" : "s")"
    }

    private var voidConfirmationMessage: String {
        let name = pendingVoid?.values.text(
            "student_name",
            fallback: "this student"
        ) ?? "this student"
        return "Void the available makeup credit for \(name)? It will remain in History with a void status."
    }

    private func matchesSearch(_ record: DynamicRecord) -> Bool {
        record.matches(search)
    }

    private func matchesProgramme(_ record: DynamicRecord) -> Bool {
        guard programmeFilter != "All programmes" else { return true }
        let source = record.values.text("source_programme")
        let target = record.values.text("target_programme")
        return source == programmeFilter || target == programmeFilter
    }

    private func load() async {
        loading = credits.isEmpty && usages.isEmpty
        defer { loading = false }
        do {
            async let loadedCredits = BackendClient.shared.select(
                table: "makeup_credits",
                query: [.init(name: "order", value: "created_at.desc")]
            )
            async let loadedUsages = BackendClient.shared.select(
                table: "makeup_usages",
                query: [.init(name: "order", value: "created_at.desc")]
            )
            async let loadedStudents = BackendClient.shared.select(table: "master_students")
            async let loadedTopUps = BackendClient.shared.select(table: "makeup_topup_payments")

            let rawCredits = try await loadedCredits
            let rawUsages = try await loadedUsages
            let students = try await loadedStudents
            let topUps = try await loadedTopUps

            let enrichedCredits = rawCredits.map { credit -> DynamicRecord in
                var values = credit.values
                let student = students.first {
                    $0.id == credit.values.text("master_student_id")
                        || $0.values.text("master_student_id") == credit.values.text("master_student_id")
                }
                values["student_name"] = .string(studentName(student))
                values["source_programme"] = .string(
                    programmeTitle(credit.values.text("source_training_type"))
                )
                return DynamicRecord(values: values)
            }

            let creditByID = Dictionary(
                uniqueKeysWithValues: enrichedCredits.map { ($0.id, $0) }
            )

            let enrichedUsages = rawUsages.map { usage -> DynamicRecord in
                var values = usage.values
                let creditID = usage.values.text(
                    "makeup_credit_id",
                    fallback: usage.values.text("credit_id")
                )
                let linkedCredit = creditByID[creditID]
                let masterStudentID = usage.values.text(
                    "master_student_id",
                    fallback: linkedCredit?.values.text("master_student_id") ?? ""
                )
                let student = students.first {
                    $0.id == masterStudentID
                        || $0.values.text("master_student_id") == masterStudentID
                }
                let sourceType = usage.values.text(
                    "source_training_type",
                    fallback: linkedCredit?.values.text("source_training_type") ?? ""
                )
                let targetType = usage.values.text("target_training_type", fallback: usage.values.text("target_type"))
                let topUp = topUps.first {
                    $0.values.text("makeup_usage_id") == usage.id
                }
                let sourceTitle = programmeTitle(sourceType)
                let targetTitle = programmeTitle(targetType)
                values["student_name"] = .string(studentName(student))
                values["source_programme"] = .string(sourceTitle)
                values["target_programme"] = .string(targetTitle)
                values["programme_change"] = .string(
                    [sourceTitle, targetTitle].filter { !$0.isEmpty }.joined(separator: " → ")
                )
                if values["credit_value_used"] == nil,
                   let linkedCredit {
                    values["credit_value_used"] = .number(linkedCredit.values.number("credit_value"))
                }
                if values["top_up_amount"] == nil, let topUp {
                    values["top_up_amount"] = .number(topUp.values.number("amount"))
                }
                if let topUp {
                    values["payment_status"] = .string(topUp.values.flag("paid") ? "paid" : "pending")
                } else if values.number("top_up_amount") <= 0 {
                    values["payment_status"] = .string("not required")
                }
                return DynamicRecord(values: values)
            }

            credits = enrichedCredits
            usages = enrichedUsages
        } catch {
            state.show(error)
        }
    }

    private func void(_ credit: DynamicRecord) async {
        let activity = state.beginActivity("Voiding makeup credit…")
        defer { state.endActivity(activity) }
        pendingVoid = nil
        do {
            _ = try await BackendClient.shared.update(
                table: "makeup_credits",
                values: [
                    "status": .string("void"),
                    "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                ],
                filters: [.init(name: "id", value: "eq.\(credit.id)")]
            )
            state.show("Makeup credit voided.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func studentName(_ student: DynamicRecord?) -> String {
        guard let student else { return "Unknown student" }
        return student.values.text(
            "display_name",
            fallback: student.values.text(
                "student_name",
                fallback: student.values.text("name", fallback: "Unknown student")
            )
        )
    }

    private func programmeTitle(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "weekend": "Weekend"
        case "weekday": "Weekday"
        case "one_to_one", "1-1", "one-to-one": "1-1"
        case "matchplay", "match_play": "MatchPlay"
        default: rawValue.isEmpty ? "" : rawValue.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func displayDate(_ rawValue: String) -> String {
        let dateKey = String(rawValue.prefix(10))
        guard !dateKey.isEmpty else { return "Not specified" }
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.calendar = Calendar(identifier: .gregorian)
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: dateKey) else { return dateKey }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func currency(_ value: Double) -> String {
        value.formatted(.currency(code: "SGD"))
    }

    private func formatNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)))
    }

    private func statusColour(_ status: String) -> Color {
        switch status.lowercased() {
        case "available": Theme.green
        case "used": Theme.blue
        case "void", "voided": Theme.red
        default: Theme.secondaryText
        }
    }
}

private enum MakeupTrackerSection: String, CaseIterable, Identifiable {
    case available
    case usage
    case history

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}
