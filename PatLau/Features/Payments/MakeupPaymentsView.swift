import SwiftUI

struct MakeupPaymentsView: View {
    @EnvironmentObject private var state: AppState

    @State private var month = Date()
    @State private var payments: [DynamicRecord] = []
    @State private var counterState: DynamicRecord?
    @State private var search = ""
    @State private var loading = false
    @State private var pendingToggle: DynamicRecord?
    @State private var showResetConfirmation = false
    @State private var showUndoConfirmation = false

    private var filtered: [DynamicRecord] {
        payments.filter { $0.matches(search) }
    }

    private var paidPayments: [DynamicRecord] {
        payments.filter { $0.values.flag("paid") }
    }

    private var paidTotal: Double {
        paidPayments.reduce(0) { $0 + $1.values.number("amount") }
    }

    private var outstandingTotal: Double {
        payments.filter { !$0.values.flag("paid") }
            .reduce(0) { $0 + $1.values.number("amount") }
    }

    private var counterTotal: Double {
        let resetDate = parsedDate(counterState?.values.text("reset_at") ?? "")
        return paidPayments.filter { payment in
            guard let resetDate else { return true }
            return parsedDate(payment.values.text("updated_at", fallback: payment.values.text("created_at"))) ?? .distantPast >= resetDate
        }
        .reduce(0) { $0 + $1.values.number("amount") }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 18) {
                HStack {
                    Label("Makeup", systemImage: "arrow.triangle.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(Theme.amber)
                    Spacer()
                    DatePicker("Month", selection: $month, displayedComponents: .date)
                        .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text(month.formatted(.dateTime.month(.wide).year()))
                        .font(.headline)
                    Text(counterTotal, format: .currency(code: "SGD"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.blue)
                    HStack(spacing: 14) {
                        Label(paidTotal.formatted(.currency(code: "SGD")), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.green)
                        Label(outstandingTotal.formatted(.currency(code: "SGD")), systemImage: "clock.fill")
                            .foregroundStyle(Theme.amber)
                    }
                    .font(.caption.weight(.semibold))

                    PaymentCounterActions(
                        canUndo: latestPaidAfterReset != nil,
                        onReset: { showResetConfirmation = true },
                        onUndo: { showUndoConfirmation = true }
                    )
                }
                .appCard()

                TextField("Search student, target or amount", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)

                HStack {
                    Text("\(filtered.count) payment record\(filtered.count == 1 ? "" : "s")")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    DataRefreshButton(
                        scope: "\(month.formatted(.dateTime.month(.wide).year())) makeup payments"
                    ) {
                        await load()
                    }
                }

                if filtered.isEmpty && !loading {
                    EmptyState(
                        icon: "dollarsign.circle",
                        title: "No makeup top-ups",
                        message: "No top-up payment records exist for this month."
                    )
                }

                ForEach(filtered) { payment in
                    VStack(spacing: 12) {
                        RecordCard(
                            record: payment,
                            titleKeys: ["student_name"],
                            detailKeys: ["target_programme", "target_date", "target_label", "credit_value_used", "target_value", "amount"],
                            query: search,
                            status: payment.values.flag("paid") ? "Paid" : "Unpaid"
                        )

                        Button {
                            pendingToggle = payment
                        } label: {
                            Label(
                                payment.values.flag("paid") ? "Mark Unpaid" : "Mark Paid",
                                systemImage: payment.values.flag("paid")
                                    ? "arrow.uturn.backward.circle.fill"
                                    : "checkmark.circle.fill"
                            )
                            .frame(maxWidth: .infinity)
                            .touchTarget()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(payment.values.flag("paid") ? Theme.amber : Theme.green)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("Makeup Payments")
        .task(id: month.monthKey) { await load() }
        .refreshable { await load() }
        .alert(
            pendingToggle?.values.flag("paid") == true ? "Reverse this payment?" : "Record this payment?",
            isPresented: Binding(
                get: { pendingToggle != nil },
                set: { if !$0 { pendingToggle = nil } }
            )
        ) {
            Button(pendingToggle?.values.flag("paid") == true ? "Mark Unpaid" : "Mark Paid") {
                if let payment = pendingToggle {
                    Task { await setPaid(payment, paid: !payment.values.flag("paid")) }
                }
            }
            Button("Cancel", role: .cancel) { pendingToggle = nil }
        } message: {
            Text("The app will update the same makeup payment record and Telegram notification as the website.")
        }
        .alert(
            "Reset the displayed total?",
            isPresented: $showResetConfirmation
        ) {
            Button("Send Summary and Reset", role: .destructive) {
                Task { await resetCounter() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Paid and unpaid records stay unchanged. A summary is sent to Telegram, matching the website.")
        }
        .alert(
            "Undo the latest payment?",
            isPresented: $showUndoConfirmation
        ) {
            Button("Undo Latest", role: .destructive) {
                if let payment = latestPaidAfterReset {
                    Task { await setPaid(payment, paid: false) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The latest paid makeup top-up after the most recent reset will be marked unpaid.")
        }
        .overlay { if loading { LoadingOverlay(text: "Loading makeup payments") } }
    }

    private var latestPaidAfterReset: DynamicRecord? {
        let resetDate = parsedDate(counterState?.values.text("reset_at") ?? "")
        return paidPayments
            .filter { payment in
                guard let resetDate else { return true }
                return parsedDate(payment.values.text("updated_at", fallback: payment.values.text("created_at"))) ?? .distantPast >= resetDate
            }
            .max {
                (parsedDate($0.values.text("updated_at", fallback: $0.values.text("created_at"))) ?? .distantPast)
                    < (parsedDate($1.values.text("updated_at", fallback: $1.values.text("created_at"))) ?? .distantPast)
            }
    }

    private func load() async {
        loading = payments.isEmpty
        defer { loading = false }

        do {
            async let loadedPayments = BackendClient.shared.select(
                table: "makeup_topup_payments",
                query: [
                    .init(name: "payment_month", value: "eq.\(month.monthKey)"),
                    .init(name: "order", value: "created_at.desc")
                ]
            )
            async let loadedStudents = BackendClient.shared.select(table: "master_students")
            async let loadedUsages = BackendClient.shared.select(table: "makeup_usages")
            async let loadedCounter = BackendClient.shared.select(
                table: "makeup_payment_counter_state",
                query: [.init(name: "payment_month", value: "eq.\(month.monthKey)")]
            )

            let rawPayments = try await loadedPayments
            let students = try await loadedStudents
            let usages = try await loadedUsages
            counterState = try await loadedCounter.first

            payments = rawPayments.map { payment in
                var values = payment.values
                let student = students.first { $0.id == payment.values.text("master_student_id") }
                let usage = usages.first { $0.id == payment.values.text("makeup_usage_id") }
                values["student_name"] = .string(student?.values.text("display_name", fallback: "Unknown student") ?? "Unknown student")
                values["target_programme"] = .string(usage?.values.text("target_training_type", fallback: "Unknown") ?? "Unknown")
                values["target_date"] = .string(usage?.values.text("target_date") ?? "")
                values["target_label"] = .string(usage?.values.text("target_label") ?? "")
                values["credit_value_used"] = usage?.values["credit_value_used"] ?? .number(0)
                values["target_value"] = usage?.values["target_value"] ?? .number(0)
                return DynamicRecord(values: values)
            }
        } catch {
            state.show(error)
        }
    }

    private func setPaid(_ payment: DynamicRecord, paid: Bool) async {
        let activity = state.beginActivity(
            paid ? "Recording makeup payment…" : "Reversing makeup payment…"
        )
        defer { state.endActivity(activity) }
        pendingToggle = nil
        do {
            let updatedAt = ISO8601DateFormatter().string(from: Date())
            let updated = try await BackendClient.shared.update(
                table: "makeup_topup_payments",
                values: ["paid": .bool(paid), "updated_at": .string(updatedAt)],
                filters: [.init(name: "id", value: "eq.\(payment.id)")]
            ).first ?? payment

            _ = try await BackendClient.shared.insert(
                table: "makeup_payment_events",
                values: [
                    "makeup_topup_payment_id": .string(payment.id),
                    "master_student_id": payment.values["master_student_id"] ?? .null,
                    "payment_month": .string(month.monthKey),
                    "amount": .number(payment.values.number("amount")),
                    "event_type": .string(paid ? "received" : "reversed"),
                    "actor_user_id": state.user.map { .string($0.id) } ?? .null
                ]
            )

            let decorated = DynamicRecord(values: updated.values.merging(payment.values) { current, _ in current })
            try await notifyTelegram(payment: decorated, paid: paid)
            state.show(paid ? "Makeup payment recorded." : "Makeup payment reversed.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
            await load()
        }
    }

    private func notifyTelegram(payment: DynamicRecord, paid: Bool) async throws {
        let title = paid ? "✅ Makeup Top-up Payment Received" : "↩️ Makeup Top-up Payment Reversed"
        let text = """
        \(title)

        Student: \(payment.values.text("student_name", fallback: "Unknown student"))
        Month: \(month.formatted(.dateTime.month(.wide).year()))
        Target Programme: \(payment.values.text("target_programme", fallback: "Unknown"))
        Amount: \(payment.values.number("amount").formatted(.currency(code: "SGD")))
        Status: \(paid ? "Paid" : "Unpaid")
        """
        _ = try await BackendClient.shared.websiteJSON(
            path: "/api/telegram-makeup-payment",
            method: "POST",
            body: ["text": .string(text)]
        )
    }

    private func resetCounter() async {
        let activity = state.beginActivity("Sending makeup payment summary and resetting the counter…")
        defer { state.endActivity(activity) }
        do {
            let summary = """
            🔄 Makeup Payment Counter Reset

            Month: \(month.formatted(.dateTime.month(.wide).year()))
            Counter Before Reset: \(counterTotal.formatted(.currency(code: "SGD")))
            Total Paid: \(paidTotal.formatted(.currency(code: "SGD")))
            Outstanding: \(outstandingTotal.formatted(.currency(code: "SGD")))
            Possible Total: \((paidTotal + outstandingTotal).formatted(.currency(code: "SGD")))
            Paid Transactions: \(paidPayments.count)

            Note: Paid/Unpaid records were not changed. Only the displayed counter was reset to S$0.00.
            """
            _ = try await BackendClient.shared.websiteJSON(
                path: "/api/telegram-makeup-payment",
                method: "POST",
                body: ["text": .string(summary)]
            )
            let now = ISO8601DateFormatter().string(from: Date())
            _ = try await BackendClient.shared.upsert(
                table: "makeup_payment_counter_state",
                values: [
                    "payment_month": .string(month.monthKey),
                    "reset_at": .string(now),
                    "reset_by": state.user.map { .string($0.id) } ?? .null,
                    "updated_at": .string(now)
                ],
                onConflict: "payment_month"
            )
            state.show("Counter reset and Telegram summary sent.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }

    private func parsedDate(_ value: String) -> Date? {
        guard !value.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
