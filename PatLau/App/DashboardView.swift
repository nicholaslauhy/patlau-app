import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var state: AppState

    let onOpenGroup: (OperationGroup) -> Void
    let onOpen: (PortalOperation) -> Void
    let onShowAllOperations: () -> Void

    @AppStorage("quickAccessOperations") private var quickAccessValue = ""
    @State private var counts: [Programme: Int] = [:]
    @State private var loading = false
    @State private var showQuickAccessEditor = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                welcomeCard

                if !homeAttendanceOperations.isEmpty {
                    SectionHeading(
                        title: "Attendance",
                        subtitle: state.role == .superuser
                            ? "View your coaching history or review attendance across every coach."
                            : "View your own coaching attendance history."
                    )

                    VStack(spacing: 0) {
                        ForEach(
                            Array(homeAttendanceOperations.enumerated()),
                            id: \.element
                        ) { index, operation in
                            Button {
                                onOpen(operation)
                            } label: {
                                OperationRow(operation: operation)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)

                            if index < homeAttendanceOperations.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .appCard(padding: 0)
                    .accessibilityIdentifier("home-attendance-section")
                }

                HStack(alignment: .bottom, spacing: 16) {
                    SectionHeading(
                        title: "Programmes",
                        subtitle: "Tap a programme to open its main workspace."
                    )
                    DataRefreshButton(scope: "programme counts") {
                        await load()
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(visibleProgrammes.enumerated()), id: \.element) { index, programme in
                        Button {
                            onOpenGroup(group(for: programme))
                        } label: {
                            programmeRow(programme)
                        }
                        .buttonStyle(.plain)

                        if index < visibleProgrammes.count - 1 {
                            Divider().padding(.leading, 58)
                        }
                    }
                }
                .appCard(padding: 0)

                if !homeSupportOperations.isEmpty {
                    SectionHeading(
                        title: "Chats & audit records",
                        subtitle: "Reply to parent conversations and review recorded account activity."
                    )

                    VStack(spacing: 0) {
                        ForEach(Array(homeSupportOperations.enumerated()), id: \.element) { index, operation in
                            Button {
                                onOpen(operation)
                            } label: {
                                OperationRow(operation: operation)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)

                            if index < homeSupportOperations.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .appCard(padding: 0)
                }

                if PortalOperation.makeupCredits.isAvailable(for: state.role) {
                    SectionHeading(
                        title: "Makeup tracking",
                        subtitle: "Track credits, completed assignments and makeup payments."
                    )

                    VStack(spacing: 0) {
                        ForEach(
                            [PortalOperation.makeupCredits, .makeupPayment],
                            id: \.self
                        ) { operation in
                            Button {
                                onOpen(operation)
                            } label: {
                                OperationRow(operation: operation)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)

                            if operation == .makeupCredits {
                                Divider()
                                    .padding(.leading, 68)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .appCard(padding: 0)
                }

                HStack(alignment: .bottom, spacing: 16) {
                    SectionHeading(
                        title: "Quick access",
                        subtitle: "Choose and arrange up to five shortcuts."
                    )
                    Button("Edit") { showQuickAccessEditor = true }
                        .font(.subheadline.weight(.semibold))
                }

                if quickOperations.isEmpty {
                    Button {
                        showQuickAccessEditor = true
                    } label: {
                        Label("Choose quick access shortcuts", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    .appCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(quickOperations.enumerated()), id: \.element) { index, operation in
                            Button {
                                onOpen(operation)
                            } label: {
                                OperationRow(operation: operation)
                                    .padding(.horizontal, 18)
                            }
                            .buttonStyle(.plain)

                            if index < quickOperations.count - 1 {
                                Divider()
                                    .padding(.leading, 68)
                                    .padding(.trailing, 18)
                            }
                        }
                    }
                    .appCard(padding: 0)
                }

                Button(action: onShowAllOperations) {
                    Label("View All Operations", systemImage: "square.grid.2x2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .touchTarget()

                NavigationLink {
                    WebPortalPage(title: "Full Web Portal", path: webPortalLandingPath)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open the Full Website")
                                .font(.subheadline.weight(.semibold))
                            Text("Access the original portal inside the app")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .padding(.vertical, 2)
                }
                .buttonStyle(.plain)
                .appCard()
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("Home")
        .refreshable {
            await load()
        }
        .task(id: state.role) { await load() }
        .sheet(isPresented: $showQuickAccessEditor) {
            QuickAccessEditor(
                role: state.role,
                initialSelection: quickOperations
            ) { operations in
                quickAccessValue = QuickAccessPreferences.encode(operations, for: state.role)
            }
        }
        .overlay {
            if loading {
                LoadingOverlay(text: "Loading dashboard")
            }
        }
    }

    private var welcomeCard: some View {
        HStack(spacing: 14) {
            UserAvatarView(
                url: state.user?.avatarURL,
                role: state.role,
                size: 52,
                revision: state.avatarRevision
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome, \(state.user?.name ?? "User")")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                HStack(spacing: 8) {
                    StatusBadge(
                        text: state.role.displayName,
                        color: Theme.colour(for: state.role)
                    )
                    if state.isResolvingRole {
                        ProgressView().controlSize(.small)
                        Text("Checking access")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .appCard()
    }

    private var visibleProgrammes: [Programme] {
        Programme.allCases.filter { programme in
            !PortalOperation.visible(
                for: state.role,
                in: group(for: programme)
            ).isEmpty
        }
    }

    private var quickOperations: [PortalOperation] {
        QuickAccessPreferences.decode(quickAccessValue, for: state.role)
    }

    private var homeAttendanceOperations: [PortalOperation] {
        PortalOperation.homeAttendance(for: state.role)
    }

    private var homeSupportOperations: [PortalOperation] {
        [PortalOperation.chats, .auditLogs].filter {
            $0.isAvailable(for: state.role)
        }
    }

    private func programmeRow(_ programme: Programme) -> some View {
        HStack(spacing: 12) {
            Image(systemName: programme.icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.colour(for: programme))
                .frame(width: 38, height: 38)
                .background(
                    Theme.colour(for: programme).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(programme.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(programmeSubtitle(programme))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private var webPortalLandingPath: String {
        "/dashboard"
    }

    private func programmeSubtitle(_ programme: Programme) -> String {
        if state.role == .superuser {
            if let count = counts[programme] {
                return "\(count) active students"
            }
            return loading ? "Loading active students…" : "Student count unavailable"
        }
        return PortalOperation.visible(for: state.role, in: group(for: programme))
            .map(\.directoryTitle)
            .joined(separator: " • ")
    }

    private func group(for programme: Programme) -> OperationGroup {
        switch programme {
        case .weekend: .weekend
        case .weekday: .weekday
        case .matchplay: .matchplay
        case .oneToOne: .oneToOne
        }
    }

    private func load() async {
        guard state.role == .superuser else {
            counts = [:]
            return
        }
        loading = counts.isEmpty
        defer { loading = false }

        await withTaskGroup(of: (Programme, Int?, String?).self) { group in
            for programme in visibleProgrammes {
                group.addTask {
                    do {
                        let records: [DynamicRecord]
                        if programme == .weekend {
                            records = try await BackendClient.shared.weekendStudents(
                                paths: WeekendStudentWebsiteRoute.dashboardSources
                            )
                        } else {
                            let query = programme.activeStudentFilter.map { [$0] } ?? []
                            records = try await BackendClient.shared.select(
                                table: programme.studentTable,
                                query: query
                            )
                        }
                        let count = records.filter {
                            programme.includesStudent(
                                active: $0.values["active"]?.bool
                            )
                        }.count
                        return (programme, count, nil)
                    } catch {
                        return (programme, nil, error.localizedDescription)
                    }
                }
            }

            var failedProgrammes: [String] = []
            for await (programme, count, message) in group {
                if let count {
                    counts[programme] = count
                } else {
                    counts[programme] = nil
                    failedProgrammes.append(
                        "\(programme.title): \(message ?? "unknown error")"
                    )
                }
            }
            if !failedProgrammes.isEmpty {
                state.show(
                    "Could not refresh programme counts. \(failedProgrammes.joined(separator: "; "))",
                    kind: .error
                )
            }
        }
    }
}

private struct QuickAccessEditor: View {
    @Environment(\.dismiss) private var dismiss

    let role: UserRole
    let onSave: ([PortalOperation]) -> Void

    @State private var selected: [PortalOperation]

    init(
        role: UserRole,
        initialSelection: [PortalOperation],
        onSave: @escaping ([PortalOperation]) -> Void
    ) {
        self.role = role
        self.onSave = onSave
        _selected = State(
            initialValue: QuickAccessPreferences.normalized(initialSelection, for: role)
        )
    }

    private var available: [PortalOperation] {
        PortalOperation.visible(for: role).filter { !selected.contains($0) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Quick Access",
                    onCancel: { dismiss() },
                    actionTitle: "Save",
                    onAction: {
                        onSave(selected)
                        dismiss()
                    }
                )

                List {
                Section {
                    if selected.isEmpty {
                        Text("No shortcuts selected")
                            .foregroundStyle(Theme.secondaryText)
                    }
                    ForEach(selected) { operation in
                        Label(operation.title, systemImage: operation.icon)
                            .foregroundStyle(Theme.ink)
                    }
                    .onMove { source, destination in
                        selected.move(fromOffsets: source, toOffset: destination)
                    }
                    .onDelete { offsets in
                        selected.remove(atOffsets: offsets)
                    }
                } header: {
                    Text("Your shortcuts (\(selected.count)/\(QuickAccessPreferences.maximumCount))")
                } footer: {
                    Text("Drag the handles to reorder. Swipe left or tap minus to remove.")
                }

                Section("Add a shortcut") {
                    if selected.count >= QuickAccessPreferences.maximumCount {
                        Text("Remove a shortcut before adding another.")
                            .foregroundStyle(Theme.secondaryText)
                    } else if available.isEmpty {
                        Text("All available operations are selected.")
                            .foregroundStyle(Theme.secondaryText)
                    } else {
                        ForEach(available) { operation in
                            Button {
                                guard selected.count < QuickAccessPreferences.maximumCount else { return }
                                selected.append(operation)
                            } label: {
                                HStack {
                                    Label(operation.title, systemImage: operation.icon)
                                    Spacer()
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundStyle(Theme.blue)
                                }
                            }
                            .foregroundStyle(Theme.ink)
                        }
                    }
                }
                }
                .environment(\.editMode, .constant(.active))
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
