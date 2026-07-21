import SwiftUI

struct CoachAttendanceView: View {
    @EnvironmentObject private var state: AppState
    @State private var topic = "saturday"
    @State private var pollDate = Date()
    @State private var intro = "Hi coaches! Please let me know your available dates:"
    @State private var venue = "The venue will be at NYGH. Please come earlier, about 1.30 to set up the courts, prep the hall.\nStart warm up at 2pm. Thanks so much!"
    @State private var sundaySlots = ["8-12pm", "10-12pm", "1-5pm"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                FilterChips(values: ["Saturday", "Sunday"], selection: Binding(get: { topic.capitalized }, set: { topic = $0.lowercased() }))
                VStack(alignment: .leading, spacing: 14) {
                    Text("Send Coach Attendance Poll").font(.title2.bold())
                    Text("Choose the actual poll date. The app creates a Telegram voting option for that date.").foregroundStyle(Theme.secondaryText)
                    DatePicker("Actual poll date", selection: $pollDate, displayedComponents: .date).datePickerStyle(.compact)
                    if topic == "sunday" {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Timing options").font(.headline)
                                Spacer()
                                Button("Add", systemImage: "plus") {
                                    sundaySlots.append("Timing \(sundaySlots.count + 1)")
                                }
                            }
                            ForEach(sundaySlots.indices, id: \.self) { index in
                                HStack {
                                    TextField("e.g. 8-12pm", text: $sundaySlots[index])
                                        .textFieldStyle(.roundedBorder)
                                    Button(role: .destructive) {
                                        guard sundaySlots.count > 1 else { return }
                                        sundaySlots.remove(at: index)
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                    }
                                    .disabled(sundaySlots.count == 1)
                                }
                            }
                        }
                    }
                    Text("Opening message").font(.headline)
                    TextEditor(text: $intro)
                        .frame(minHeight: 105)
                        .padding(8)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Opening message")
                        .accessibilityIdentifier("coach-poll-intro")
                    Text("Venue and closing message").font(.headline)
                    TextEditor(text: $venue)
                        .frame(minHeight: 135)
                        .padding(8)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Venue and closing message")
                        .accessibilityIdentifier("coach-poll-venue")
                    messagePreview
                    AsyncActionButton(
                        title: "Send \(topic.capitalized) Coaching",
                        progressTitle: "Sending poll…",
                        icon: "paperplane.fill",
                        disabled: intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ) { await send() }
                }.appCard()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }.navigationTitle("Coach Attendance")
        .onAppear { configureDay(topic) }
        .onChange(of: topic) { _, value in configureDay(value) }
    }

    private var messagePreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Telegram Preview", systemImage: "paperplane.fill")
                .font(.headline)
                .foregroundStyle(Theme.blue)

            Text("Opening message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Your opening message will appear here."
                : intro.trimmingCharacters(in: .whitespacesAndNewlines))
                .foregroundStyle(intro.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Theme.secondaryText
                    : Theme.ink)

            Divider()

            Text("\(topic.capitalized) Coaching Poll")
                .font(.subheadline.weight(.semibold))
            Text(pollDate.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)

            ForEach(Array(previewOptions.enumerated()), id: \.offset) { _, option in
                Label(option, systemImage: "circle")
                    .font(.subheadline)
            }

            Divider()

            Text("Closing message")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Your venue and closing message will appear here."
                : venue.trimmingCharacters(in: .whitespacesAndNewlines))
                .foregroundStyle(venue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Theme.secondaryText
                    : Theme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.blue.opacity(0.18), lineWidth: 1)
        )
        .accessibilityIdentifier("coach-poll-preview")
    }

    private var previewOptions: [String] {
        if topic == "saturday" {
            return [pollDate.formatted(.dateTime.day().month(.wide).year())]
        }
        let options = sundaySlots
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return options.isEmpty ? ["Your timing options will appear here."] : options
    }

    private func send() async {
        guard state.role.permissionRank >= UserRole.admin.permissionRank else {
            state.show("Your account cannot send coach attendance polls.", kind: .error)
            return
        }
        let activity = state.beginActivity("Sending Telegram coaching poll…")
        defer { state.endActivity(activity) }
        let slots: [JSONValue]
        if topic == "saturday" {
            let label = pollDate.formatted(.dateTime.day().month(.wide).year())
            slots = [.object(["key": .string(pollDate.isoDateKey), "label": .string(label)])]
        } else {
            do {
                slots = try sundaySlots.map { label in
                    let hours = try parsedHours(label)
                    return .object([
                        "key": .string("\(pollDate.isoDateKey)-\(hours.start)-\(hours.end)"),
                        "label": .string(label.trimmingCharacters(in: .whitespacesAndNewlines))
                    ])
                }
            } catch {
                state.show(error.localizedDescription, kind: .error)
                return
            }
        }
        do {
            _ = try await BackendClient.shared.websiteJSON(path: "/api/telegram-coach-attendance/send", method: "POST", body: ["introText": .string(intro.trimmingCharacters(in: .whitespacesAndNewlines)), "venueText": .string(venue), "pollDate": .string(pollDate.isoDateKey), "topic": .string(topic), "slots": .array(slots)])
            state.show("Telegram poll sent.")
        } catch { state.show(error.localizedDescription, kind: .error) }
    }

    private func parsedHours(_ label: String) throws -> (start: Int, end: Int) {
        let pattern = #"^(\d{1,2})\s*-\s*(\d{1,2})"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: label,
                range: NSRange(label.startIndex..., in: label)
              ),
              let startRange = Range(match.range(at: 1), in: label),
              let endRange = Range(match.range(at: 2), in: label),
              let start = Int(label[startRange]),
              let end = Int(label[endRange]) else {
            throw BackendError.message("Use timing labels such as 8-12pm.")
        }
        return (start, end)
    }

    private func configureDay(_ value: String) {
        let targetWeekday = value == "saturday" ? 7 : 1
        let calendar = Calendar.current
        let todayWeekday = calendar.component(.weekday, from: Date())
        var days = (targetWeekday - todayWeekday + 7) % 7
        if days == 0 { days = 7 }
        pollDate = calendar.date(byAdding: .day, value: days, to: Date()) ?? Date()
        intro = value == "saturday"
            ? "Hi coaches! Please let me know your available dates for \(pollDate.formatted(.dateTime.month(.wide))):"
            : "Hi coaches! Please let me know your availability for \(pollDate.formatted(.dateTime.month(.wide))):"
        venue = value == "saturday"
            ? "The venue will be at NYGH. Please come earlier, about 1.30 to set up the courts, prep the hall.\nStart warm up at 2pm. Thanks so much!"
            : "The venue will be at NYGH. Please come earlier to set up the courts and prep the hall.\nThanks so much!"
    }
}
