import SwiftUI

struct RootView: View {
    @EnvironmentObject private var state: AppState

    @State private var selectedTab: AppTab = .home
    @State private var homePath: [AppRoute] = []
    @State private var operationsPath: [AppRoute] = []
    @State private var showLogoutConfirmation = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $homePath) {
                DashboardView(
                    onOpenGroup: { homePath.append(.group($0)) },
                    onOpen: { homePath.append(.operation($0)) },
                    onShowAllOperations: { selectedTab = .operations }
                )
                .appTabBarClearance()
                .appNoticeHost()
                .navigationDestination(for: AppRoute.self) { route in
                    destination(for: route)
                }
                .appAccountToolbar(onLogout: { showLogoutConfirmation = true })
            }
            .tag(AppTab.home)
            .tabItem {
                Label("Home", systemImage: "house.fill")
            }

            NavigationStack(path: $operationsPath) {
                OperationsView()
                    .appTabBarClearance()
                    .appNoticeHost()
                    .navigationDestination(for: AppRoute.self) { route in
                        destination(for: route)
                    }
                    .appAccountToolbar(onLogout: { showLogoutConfirmation = true })
            }
            .tag(AppTab.operations)
            .tabItem {
                Label("Operations", systemImage: "square.grid.2x2.fill")
            }

            NavigationStack {
                SettingsView()
                    .appTabBarClearance()
                    .appNoticeHost()
                    .appAccountToolbar(onLogout: { showLogoutConfirmation = true })
            }
            .tag(AppTab.account)
            .tabItem {
                Label("Account", systemImage: "person.crop.circle.fill")
            }
        }
        .allowsHitTesting(state.activity == nil)
        .background(Theme.background)
        .overlay {
            if let activity = state.activity {
                LoadingOverlay(text: activity.message)
                    .transition(.opacity)
                    .zIndex(30)
            }
        }
        .animation(.easeInOut(duration: 0.22), value: state.notice?.id)
        .animation(.easeInOut(duration: 0.18), value: state.activity?.id)
        .confirmationDialog(
            "Log out of PatLau?",
            isPresented: $showLogoutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                state.signOut()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You will need to enter your account details again to use the app.")
        }
        .onChange(of: state.role) { _, role in
            homePath.removeAll { !$0.isAvailable(for: role) }
            operationsPath.removeAll { !$0.isAvailable(for: role) }
        }
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case .group(let group):
            ProgrammeDirectoryView(group: group)
                .appTabBarClearance()
                .appNoticeHost()
        case .operation(let operation):
            if operation.isAvailable(for: state.role) {
                NativeOperationDestination(operation: operation)
                    .appTabBarClearance()
                    .appNoticeHost()
            } else {
                AccessDeniedView(operation: operation)
                    .appNoticeHost()
            }
        }
    }
}

private extension AppRoute {
    func isAvailable(for role: UserRole) -> Bool {
        switch self {
        case .group(let group):
            !PortalOperation.visible(for: role, in: group).isEmpty
        case .operation(let operation):
            operation.isAvailable(for: role)
        }
    }
}

private struct AccessDeniedView: View {
    let operation: PortalOperation

    var body: some View {
        ContentUnavailableView {
            Label("Access Restricted", systemImage: "lock.fill")
        } description: {
            Text("Your current account role cannot access \(operation.title).")
        }
        .navigationTitle(operation.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AccountToolbarModifier: ViewModifier {
    @EnvironmentObject private var state: AppState
    let onLogout: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Section {
                        Label(
                            "Signed in as \(state.user?.name ?? "User")",
                            systemImage: "person.fill"
                        )
                        Label(state.role.displayName, systemImage: "checkmark.shield.fill")
                    }

                    Button(role: .destructive, action: onLogout) {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    if state.isResolvingRole {
                        ProgressView()
                            .frame(width: 32, height: 32)
                    } else {
                        UserAvatarView(
                            url: state.user?.avatarURL,
                            role: state.role,
                            size: 32,
                            revision: state.avatarRevision
                        )
                    }
                }
            }
        }
    }
}

private extension View {
    func appAccountToolbar(onLogout: @escaping () -> Void) -> some View {
        modifier(AccountToolbarModifier(onLogout: onLogout))
    }
}
