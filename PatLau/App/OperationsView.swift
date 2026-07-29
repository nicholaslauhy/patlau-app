import SwiftUI

struct OperationsView: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("quickAccessOperations") private var quickAccessValue = ""

    @State private var search = ""
    @State private var showQuickAccessEditor = false

    private let programmeGroups: [OperationGroup] = [
        .weekend,
        .weekday,
        .matchplay,
        .oneToOne
    ]

    private var searchTerm: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var quickOperations: [PortalOperation] {
        QuickAccessPreferences.decode(quickAccessValue, for: state.role)
            .filter(matchesSearch)
    }

    private var visibleProgrammeGroups: [OperationGroup] {
        programmeGroups.filter(isVisible)
    }

    private var showsMakeup: Bool {
        isVisible(.makeup)
    }

    private var showsSupport: Bool {
        isVisible(.support)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                workspaceIntroduction

                if searchTerm.isEmpty || !quickOperations.isEmpty {
                    quickAccessSection
                }

                if !visibleProgrammeGroups.isEmpty {
                    workspaceSection(
                        title: "Programmes",
                        subtitle: "Weekend, Weekday, MatchPlay and 1-1 tools stay together."
                    ) {
                        groupCard(visibleProgrammeGroups)
                    }
                }

                if showsMakeup {
                    workspaceSection(
                        title: "Makeup",
                        subtitle: "Credits and makeup payments are kept separate from programmes."
                    ) {
                        groupCard([.makeup])
                    }
                }

                if showsSupport {
                    workspaceSection(
                        title: "Support & records",
                        subtitle: "Parent conversations, audit records and coaching attendance."
                    ) {
                        groupCard([.support])
                    }
                }

                if searchTerm.isEmpty {
                    fullWebsiteLink
                }

                if !searchTerm.isEmpty,
                   quickOperations.isEmpty,
                   visibleProgrammeGroups.isEmpty,
                   !showsMakeup,
                   !showsSupport {
                    ContentUnavailableView.search(text: search)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 20)
        }
        .background(Theme.background)
        .navigationTitle("Workspace")
        .searchable(text: $search, prompt: "Search workspace")
        .sheet(isPresented: $showQuickAccessEditor) {
            QuickAccessEditor(
                role: state.role,
                initialSelection: QuickAccessPreferences.decode(
                    quickAccessValue,
                    for: state.role
                )
            ) { operations in
                quickAccessValue = QuickAccessPreferences.encode(
                    operations,
                    for: state.role
                )
            }
        }
        .overlay {
            if state.isResolvingRole {
                LoadingOverlay(text: "Checking account access")
            }
        }
    }

    private var workspaceIntroduction: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "square.grid.2x2.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .frame(width: 46, height: 46)
                .background(
                    Theme.blue.opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 13)
                )

            VStack(alignment: .leading, spacing: 5) {
                Text("Your operational workspace")
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text("Open detailed tools without crowding the Home command centre.")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var quickAccessSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SectionHeading(
                    title: "Quick access",
                    subtitle: "Choose and arrange up to five shortcuts."
                )

                Spacer(minLength: 8)

                Button("Edit") {
                    showQuickAccessEditor = true
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.blue)
                .touchTarget()
            }

            if quickOperations.isEmpty {
                Text(
                    searchTerm.isEmpty
                        ? "Choose Edit to add your most-used tools."
                        : "No shortcuts match your search."
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .appCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(quickOperations.enumerated()), id: \.element) {
                        index,
                        operation in
                        NavigationLink(value: AppRoute.operation(operation)) {
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
        }
    }

    private func workspaceSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: title, subtitle: subtitle)
            content()
        }
    }

    private func groupCard(_ groups: [OperationGroup]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                NavigationLink(value: AppRoute.group(group)) {
                    workspaceGroupRow(group)
                        .padding(.horizontal, 18)
                }
                .buttonStyle(.plain)

                if index < groups.count - 1 {
                    Divider()
                        .padding(.leading, 72)
                        .padding(.trailing, 18)
                }
            }
        }
        .appCard(padding: 0)
    }

    private func workspaceGroupRow(_ group: OperationGroup) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: group.icon)
                .font(.headline.weight(.semibold))
                .foregroundStyle(Theme.colour(for: group))
                .frame(width: 40, height: 44)

            VStack(alignment: .leading, spacing: 5) {
                Text(group.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(directorySummary(group))
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
        .padding(.vertical, 12)
    }

    private var fullWebsiteLink: some View {
        NavigationLink {
            WebPortalPage(
                title: "Full Web Portal",
                path: "/dashboard"
            )
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "globe")
                    .font(.headline)
                    .foregroundStyle(Theme.teal)
                    .frame(width: 40, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text("Open the Full Website")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text("Use the original portal with your current PatLau session")
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 10)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .appCard()
    }

    private func isVisible(_ group: OperationGroup) -> Bool {
        guard group != .account else { return false }
        let operations = PortalOperation.visible(for: state.role, in: group)
        guard !operations.isEmpty else { return false }
        guard !searchTerm.isEmpty else { return true }
        return group.title.localizedCaseInsensitiveContains(searchTerm)
            || operations.contains(where: matchesSearch)
    }

    private func matchesSearch(_ operation: PortalOperation) -> Bool {
        guard !searchTerm.isEmpty else { return true }
        return operation.title.localizedCaseInsensitiveContains(searchTerm)
            || operation.subtitle.localizedCaseInsensitiveContains(searchTerm)
            || operation.directoryTitle.localizedCaseInsensitiveContains(searchTerm)
    }

    private func directorySummary(_ group: OperationGroup) -> String {
        PortalOperation.visible(for: state.role, in: group)
            .map(\.directoryTitle)
            .joined(separator: " • ")
    }
}
