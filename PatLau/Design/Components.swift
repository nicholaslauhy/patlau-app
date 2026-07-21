import SwiftUI

struct DataRefreshButton: View {
    let scope: String
    let action: () async -> Void

    @State private var refreshing = false

    var body: some View {
        Button {
            guard !refreshing else { return }
            refreshing = true
            Task {
                defer { refreshing = false }
                await action()
            }
        } label: {
            HStack(spacing: 6) {
                if refreshing {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
                Text(refreshing ? "Refreshing" : "Refresh")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.blue)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(refreshing)
        .accessibilityLabel(
            refreshing ? "Refreshing \(scope)" : "Refresh \(scope)"
        )
        .accessibilityIdentifier("data-refresh")
    }
}

struct PaymentCounterActions: View {
    var canUndo = true
    let onReset: () -> Void
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            Button(action: onReset) {
                Label("Reset Total", systemImage: "arrow.counterclockwise")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.red)
            .accessibilityIdentifier("payment-reset-total")

            Spacer(minLength: 8)

            Button(action: onUndo) {
                Label("Undo Latest", systemImage: "arrow.uturn.backward")
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.amber)
            .disabled(!canUndo)
            .accessibilityIdentifier("payment-undo-latest")
        }
    }
}

struct UserAvatarView: View {
    let url: URL?
    var role: UserRole = .member
    var size: CGFloat = 44
    var revision: UUID? = nil

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: cacheBusted(url)) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Theme.border, lineWidth: 1))
        .accessibilityLabel(url == nil ? "Default account profile" : "Account profile photo")
    }

    private var fallback: some View {
        ZStack {
            Theme.colour(for: role).opacity(0.12)
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .padding(size * 0.14)
                .foregroundStyle(Theme.colour(for: role))
        }
    }

    private func cacheBusted(_ url: URL) -> URL {
        guard let revision,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        items.removeAll { $0.name == "app_avatar_revision" }
        items.append(URLQueryItem(name: "app_avatar_revision", value: revision.uuidString))
        components.queryItems = items
        return components.url ?? url
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 38, height: 38)
                .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .appCard(padding: 12)
    }
}

struct RecordCard: View {
    let record: DynamicRecord
    let titleKeys: [String]
    let detailKeys: [String]
    var query = ""
    var status: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                SearchHighlight(text: title, query: query)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Spacer(minLength: 8)
                if let status, !status.isEmpty {
                    StatusBadge(text: status, color: statusColor)
                }
            }

            ForEach(detailKeys.filter { !record.values.text($0).isEmpty }, id: \.self) { key in
                HStack(alignment: .top, spacing: 8) {
                    Text(label(key))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 88, alignment: .leading)
                    SearchHighlight(text: record.values.text(key), query: query)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
            }
        }
        .appCard()
    }

    private var title: String {
        titleKeys.lazy
            .map { record.values.text($0) }
            .first { !$0.isEmpty } ?? "Record"
    }

    private var statusColor: Color {
        switch status?.lowercased() {
        case "paid", "published", "attended", "available": Theme.green
        case "missed", "unpaid", "escalated": Theme.red
        case "draft", "human_active": Theme.amber
        default: Theme.blue
        }
    }

    private func label(_ key: String) -> String {
        if key == "student_levelofplay" { return "Student Level of Play" }
        return key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct FilterChips: View {
    let values: [String]
    @Binding var selection: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(values, id: \.self) { value in
                    Button(value) { selection = value }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(selection == value ? .white : Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            selection == value ? Theme.blue : Color(uiColor: .systemGray5),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ProgrammePicker: View {
    @Binding var selection: Programme
    var programmes: [Programme] = Programme.allCases

    var body: some View {
        Picker("Programme", selection: $selection) {
            ForEach(programmes) { programme in
                Label(programme.title, systemImage: programme.icon)
                    .tag(programme)
            }
        }
        .pickerStyle(.menu)
        .buttonStyle(.plain)
    }
}

struct AppSearchField: View {
    let prompt: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)

            TextField(prompt, text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 48)
        .background(Theme.raisedBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Theme.border, lineWidth: 1)
        )
    }
}

struct WeekendFilterPanel: View {
    @Binding var day: String
    @Binding var timeslot: String
    @Binding var level: String

    private var availableTimeslots: [String] {
        let slots: [String]
        switch day {
        case "Saturday": slots = WeekendSchedule.saturdayTimeslots
        case "Sunday": slots = WeekendSchedule.sundayTimeslots
        default: slots = WeekendSchedule.allTimeslots
        }
        return ["All timeslots"] + slots
    }

    private var hasSelection: Bool {
        day != "All days" || timeslot != "All timeslots" || level != "All levels"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Filter students", systemImage: "line.3.horizontal.decrease")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.ink)

                Spacer()

                if hasSelection {
                    Button("Clear") {
                        day = "All days"
                        timeslot = "All timeslots"
                        level = "All levels"
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.blue)
                }
            }

            Picker("Training day", selection: $day) {
                ForEach(["All days", "Saturday", "Sunday"], id: \.self) {
                    Text($0)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: day) { _, _ in
                if !availableTimeslots.contains(timeslot) {
                    timeslot = "All timeslots"
                }
            }

            HStack(spacing: 12) {
                filterMenu(
                    title: "Timeslot",
                    selection: $timeslot,
                    values: availableTimeslots
                )
                filterMenu(
                    title: "Level",
                    selection: $level,
                    values: ["All levels", "Beginner", "Intermediate", "Advanced"]
                )
            }
        }
        .appCard()
    }

    private func filterMenu(
        title: String,
        selection: Binding<String>,
        values: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.secondaryText)

            Menu {
                ForEach(values, id: \.self) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        if selection.wrappedValue == value {
                            Label(value, systemImage: "checkmark")
                        } else {
                            Text(value)
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Text(selection.wrappedValue)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AsyncActionButton: View {
    let title: String
    var progressTitle: String? = nil
    var icon: String? = nil
    var role: ButtonRole? = nil
    var disabled = false
    var fillsWidth = true
    let action: () async -> Void

    @State private var busy = false

    var body: some View {
        Button(role: role) {
            busy = true
            Task {
                await action()
                busy = false
            }
        } label: {
            HStack(spacing: 8) {
                if busy {
                    ProgressView()
                } else if let icon {
                    Image(systemName: icon)
                }
                Text(busy ? (progressTitle ?? "Working…") : title)
            }
            .frame(maxWidth: fillsWidth ? .infinity : nil)
        }
        .buttonStyle(AppPrimaryButtonStyle())
        .disabled(disabled || busy)
        .touchTarget()
    }
}

struct OperationRow: View {
    let operation: PortalOperation

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: operation.icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.colour(for: operation.group))
                .frame(width: 32, height: 40)

            VStack(alignment: .leading, spacing: 5) {
                Text(operation.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(operation.subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.tint, in: RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.35)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(.tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? (configuration.isPressed ? 0.65 : 1) : 0.35)
    }
}

struct InlineNumberStepper: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Button { value -= 1 } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)

            Text("\(value)")
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 28)

            Button { value += 1 } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
        }
    }
}

struct InlineDecimalStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 0.5

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer()
            Button { value = max(range.lowerBound, value - step) } label: {
                Image(systemName: "minus")
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value <= range.lowerBound)

            Text(value.formatted(.number.precision(.fractionLength(0...2))))
                .font(.body.monospacedDigit().weight(.semibold))
                .frame(minWidth: 42)

            Button { value = min(range.upperBound, value + step) } label: {
                Image(systemName: "plus")
                    .frame(width: 36, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(value >= range.upperBound)
        }
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PlainSheetHeader: View {
    let title: String
    var cancelTitle = "Cancel"
    var cancelDisabled = false
    let onCancel: () -> Void
    var actionTitle: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                Button(cancelTitle, action: onCancel)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.blue)
                    .disabled(cancelDisabled)

                Spacer(minLength: 16)

                if let actionTitle, let onAction {
                    Button(actionTitle, action: onAction)
                        .buttonStyle(.plain)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.blue)
                }
            }

            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Color(uiColor: .systemGroupedBackground))
    }
}
