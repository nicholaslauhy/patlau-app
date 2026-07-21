import SwiftUI

struct OperationsView: View {
    @EnvironmentObject private var state: AppState
    @State private var search = ""

    private var groups: [OperationGroup] {
        OperationGroup.allCases.filter { group in
            guard group != .account else { return false }
            let groupOperations = PortalOperation.visible(for: state.role, in: group)
            guard !groupOperations.isEmpty else { return false }
            let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }
            return group.title.localizedCaseInsensitiveContains(term)
                || groupOperations.contains {
                    $0.title.localizedCaseInsensitiveContains(term)
                        || $0.subtitle.localizedCaseInsensitiveContains(term)
                }
        }
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WebPortalPage(
                        title: "Full Web Portal",
                        path: "/dashboard"
                    )
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "globe")
                            .foregroundStyle(Theme.teal)
                            .frame(width: 36, height: 36)
                            .background(Theme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Full Web Portal")
                                .font(.body.weight(.semibold))
                            Text("Use the original website without leaving the app")
                                .font(.caption)
                                .foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } footer: {
                Text("The embedded website receives your current PatLau session, so the original portal opens without a separate sign-in.")
            }

            Section("Programme directories") {
                ForEach(groups) { group in
                    NavigationLink(value: AppRoute.group(group)) {
                        HStack(spacing: 12) {
                            Image(systemName: group.icon)
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(Theme.colour(for: group))
                                .frame(width: 40, height: 40)
                                .background(
                                    Theme.colour(for: group).opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 11)
                                )

                            VStack(alignment: .leading, spacing: 3) {
                                Text(group.title)
                                    .font(.body.weight(.semibold))
                                Text(directorySummary(group))
                                    .font(.caption)
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Operations")
        .searchable(text: $search, prompt: "Search operations")
        .overlay {
            if state.isResolvingRole {
                LoadingOverlay(text: "Checking account access")
            }
        }
    }

    private func directorySummary(_ group: OperationGroup) -> String {
        let titles = PortalOperation.visible(for: state.role, in: group)
            .map(\.directoryTitle)
        return titles.joined(separator: " • ")
    }
}
