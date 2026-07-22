import SwiftUI
import PhotosUI
import UIKit

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var profilePreview: UIImage?
    @State private var showCropper = false
    @State private var showCamera = false
    @State private var showRemovePhotoConfirmation = false
    @State private var showSignOutConfirmation = false

    @State private var users: [DynamicRecord] = []
    @State private var profileHandles: [String: String] = [:]
    @State private var userSearch = ""
    @State private var loadingUsers = false
    @State private var showAddUser = false

    @State private var showPasswordForm = false
    @State private var newPassword = ""
    @State private var revealPassword = false

    private var canManageUsers: Bool {
        state.role == .admin || state.role == .superuser
    }

    private var filteredUsers: [DynamicRecord] {
        users.filter { user in
            let permitted = state.role == .superuser || resolvedRole(user) == .member
            guard permitted else { return false }

            let term = userSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }

            return displayName(user).localizedCaseInsensitiveContains(term)
                || user.values.text("email").localizedCaseInsensitiveContains(term)
                || resolvedRole(user).displayName.localizedCaseInsensitiveContains(term)
        }
    }

    var body: some View {
        List {
            profileSection
            photoSection
            securitySection

            if state.role == .superuser {
                telegramSupportAdminSection
            }

            if canManageUsers {
                userManagementSection
            }

            Section {
                Button(role: .destructive) {
                    showSignOutConfirmation = true
                } label: {
                    Label("Log Out of PatLau", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Account")
        .refreshable {
            await state.refreshAccount()
            if canManageUsers { await loadUsers() }
        }
        .task(id: state.role) {
            if canManageUsers {
                await loadUsers()
            } else {
                users = []
                profileHandles = [:]
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task { await loadPhoto(item) }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker(
                onImage: { image in
                    sourceImage = image
                    showCamera = false
                    showCropper = true
                },
                onCancel: { showCamera = false }
            )
            .ignoresSafeArea()
        }
        .sheet(
            isPresented: $showCropper,
            onDismiss: {
                sourceImage = nil
                selectedPhoto = nil
            }
        ) {
            if let sourceImage {
                PhotoCropper(image: sourceImage) { data in
                    try await upload(data)
                }
            }
        }
        .sheet(isPresented: $showAddUser) {
            AddManagedUserSheet(callerRole: state.role) {
                await loadUsers()
            }
        }
        .confirmationDialog(
            "Remove your profile photo?",
            isPresented: $showRemovePhotoConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove Photo", role: .destructive) {
                Task { await removePhoto() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your account will return to the default initial avatar.")
        }
        .confirmationDialog(
            "Log out of PatLau?",
            isPresented: $showSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Log Out", role: .destructive) {
                state.signOut()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var profileSection: some View {
        Section {
            HStack(spacing: 14) {
                AvatarView(
                    url: state.user?.avatarURL,
                    name: state.user?.name ?? "User",
                    size: 64,
                    localImage: profilePreview
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(state.user?.name ?? "User")
                        .font(.headline)
                    Text(state.user?.email ?? "")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .textSelection(.enabled)
                    StatusBadge(
                        text: state.role.displayName,
                        color: Theme.colour(for: state.role)
                    )
                }

                Spacer(minLength: 0)

                if state.isResolvingRole {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Refreshing account access")
                }
            }
            .padding(.vertical, 4)

        } header: {
            Text("Signed-in Account")
        } footer: {
            Text("Your photo and permissions update automatically after account changes.")
        }
    }

    private var photoSection: some View {
        Section {
            PhotosPicker(selection: $selectedPhoto, matching: .images) {
                Label("Choose Photo from Library", systemImage: "photo.on.rectangle")
            }

            Button {
                showCamera = true
            } label: {
                Label("Take a New Photo", systemImage: "camera.fill")
            }
            .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))

            if profilePreview != nil || state.user?.avatarURL != nil {
                Button(role: .destructive) {
                    showRemovePhotoConfirmation = true
                } label: {
                    Label("Remove Current Photo", systemImage: "person.crop.circle.badge.minus")
                }
            }
        } header: {
            Text("Profile Photo")
        } footer: {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Text("Choose an existing image or take a new one, then crop it before saving.")
            } else {
                Text("The camera is unavailable on this device. You can still choose an image from the photo library.")
            }
        }
    }

    private var securitySection: some View {
        Section {
            if showPasswordForm {
                HStack(spacing: 8) {
                    Group {
                        if revealPassword {
                            TextField("New password", text: $newPassword)
                        } else {
                            SecureField("New password", text: $newPassword)
                        }
                    }
                    .textContentType(.newPassword)

                    Button {
                        revealPassword.toggle()
                    } label: {
                        Image(systemName: revealPassword ? "eye.slash" : "eye")
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(revealPassword ? "Hide password" : "Show password")
                }

                AsyncActionButton(
                    title: "Update Password",
                    progressTitle: "Updating password…",
                    icon: "lock.rotation",
                    disabled: newPassword.count < 8
                ) {
                    await changePassword()
                }

                Button("Cancel") {
                    showPasswordForm = false
                    newPassword = ""
                    revealPassword = false
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.blue)
            } else {
                Button {
                    showPasswordForm = true
                } label: {
                    Label("Change Password", systemImage: "key.fill")
                }
            }
        } header: {
            Text("Security")
        } footer: {
            if showPasswordForm {
                Text("Use at least eight characters.")
            }
        }
    }

    private var userManagementSection: some View {
        Section {
            Button {
                showAddUser = true
            } label: {
                Label("Add User Account", systemImage: "person.badge.plus")
            }

            TextField("Search users", text: $userSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if loadingUsers && users.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading users…")
                        .foregroundStyle(Theme.secondaryText)
                }
            } else if filteredUsers.isEmpty {
                Text("No user accounts match this search.")
                    .foregroundStyle(Theme.secondaryText)
            } else {
                ForEach(filteredUsers) { user in
                    NavigationLink {
                        ManagedUserDetailView(
                            user: user,
                            telegramHandle: profileHandles[user.id] ?? "",
                            callerRole: state.role,
                            currentUserID: state.user?.id,
                            onChanged: { await loadUsers() }
                        )
                    } label: {
                        ManagedUserRow(user: user)
                    }
                }
            }
        } header: {
            HStack {
                Text("User Administration")
                Spacer()
                DataRefreshButton(scope: "user administration") {
                    await loadUsers()
                }
            }
        } footer: {
            Text(
                state.role == .admin
                    ? "Admins can create, reset and remove member accounts."
                    : "Superusers can create accounts, change roles, link Telegram handles and manage password resets."
            )
        }
    }

    private var telegramSupportAdminSection: some View {
        Section {
            NavigationLink {
                TelegramSupportAdministratorsView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Telegram Administrators")
                            .foregroundStyle(Theme.ink)
                        Text("Manage parent-support alert recipients")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                } icon: {
                    Image(systemName: "paperplane.circle.fill")
                        .foregroundStyle(Theme.blue)
                }
            }
        } header: {
            Text("Parent Support Bot")
        } footer: {
            Text("Only superusers can add, disable, or remove Telegram support administrators.")
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            return
        }

        selectedPhoto = nil
        sourceImage = image
        showCropper = true
    }

    private func upload(_ data: Data) async throws {
        _ = try await BackendClient.shared.uploadProfilePhoto(data)
        profilePreview = UIImage(data: data)
        await state.refreshAccount()
        state.reloadAvatar()
        state.show("Profile photo updated.")
    }

    private func removePhoto() async {
        let activity = state.beginActivity("Removing profile photo…")
        defer { state.endActivity(activity) }
        do {
            try await BackendClient.shared.deleteProfilePhoto()
            profilePreview = nil
            sourceImage = nil
            await state.refreshAccount()
            state.reloadAvatar()
            state.show("Profile photo removed.")
        } catch {
            state.show(error)
        }
    }

    private func changePassword() async {
        let activity = state.beginActivity("Updating account password…")
        defer { state.endActivity(activity) }
        do {
            try await BackendClient.shared.updatePassword(newPassword)
            newPassword = ""
            revealPassword = false
            showPasswordForm = false
            state.show("Password updated.")
        } catch {
            state.show(error)
        }
    }

    private func loadUsers() async {
        guard canManageUsers else { return }
        loadingUsers = true
        defer { loadingUsers = false }

        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "/api/users/list"
            )
            let loadedUsers = response.object?["users"]?.array?
                .compactMap(\.object)
                .map(DynamicRecord.init) ?? []
            users = loadedUsers.sorted { displayName($0) < displayName($1) }
        } catch {
            state.show(error)
            return
        }

        do {
            let profiles = try await BackendClient.shared.select(
                table: "coach_profiles"
            )
            var handles: [String: String] = [:]
            for profile in profiles {
                let userID = profile.values.text("auth_user_id")
                guard !userID.isEmpty else { continue }
                handles[userID] = profile.values.text("telegram_handle")
            }
            profileHandles = handles
        } catch {
            // User administration still works when Telegram profiles are unavailable.
            profileHandles = [:]
        }
    }

    private func displayName(_ user: DynamicRecord) -> String {
        user.values["user_metadata"]?.object?.text(
            "name",
            fallback: user.values.text("email", fallback: "User")
        ) ?? "User"
    }

    private func resolvedRole(_ user: DynamicRecord) -> UserRole {
        if let value = user.values["app_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }

        if let value = user.values["user_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }

        return .member
    }
}

enum TelegramSupportAdminWebsiteRoute {
    static let administrators = "/api/telegram-support-admins"
    static let test = "/api/telegram-support-admins/test"
    static let identityCommand = "/myid"
}

struct TelegramSupportAdministrator: Identifiable, Equatable {
    let id: String
    let displayName: String
    let chatIDHint: String
    let active: Bool
    let deploymentFallback: Bool
    let managedRecord: Bool

    init?(values: JSONObject) {
        let id = values.text("id")
        let displayName = values.text("display_name")
        let chatIDHint = values.text("chat_id_hint")
        guard !id.isEmpty, !displayName.isEmpty, !chatIDHint.isEmpty else { return nil }

        self.id = id
        self.displayName = displayName
        self.chatIDHint = chatIDHint
        active = values.flag("active")
        deploymentFallback = values.flag("deployment_fallback")
        managedRecord = true
    }

    private init(
        id: String,
        displayName: String,
        chatIDHint: String,
        active: Bool,
        deploymentFallback: Bool,
        managedRecord: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.chatIDHint = chatIDHint
        self.active = active
        self.deploymentFallback = deploymentFallback
        self.managedRecord = managedRecord
    }

    static func environmentPrimary(chatIDHint: String) -> TelegramSupportAdministrator {
        TelegramSupportAdministrator(
            id: "vercel-primary-administrator",
            displayName: "Primary Administrator",
            chatIDHint: chatIDHint,
            active: true,
            deploymentFallback: true,
            managedRecord: false
        )
    }

    var maskedChatID: String {
        chatIDHint.isEmpty
            ? "Configured securely in Vercel"
            : "Telegram ID \(chatIDHint)"
    }
}

struct TelegramSupportFallback: Equatable {
    var configured = false
    var represented = false
    var chatIDHint = ""

    init() {}

    init(values: JSONObject) {
        configured = values.flag("configured")
        represented = values.flag("represented")
        chatIDHint = values.text("chat_id_hint")
    }
}

func isValidTelegramSupportChatID(_ value: String) -> Bool {
    value.range(
        of: #"^[0-9]{5,20}$"#,
        options: .regularExpression
    ) != nil
}

private struct TelegramSupportAdministratorsView: View {
    @EnvironmentObject private var state: AppState

    @State private var administrators: [TelegramSupportAdministrator] = []
    @State private var loading = false
    @State private var loadFailed = false
    @State private var fallback = TelegramSupportFallback()
    @State private var effectiveActiveCount = 0
    @State private var pendingRemoval: TelegramSupportAdministrator?
    @State private var showRemovalConfirmation = false

    private var allAdministrators: [TelegramSupportAdministrator] {
        (fallback.configured && !fallback.represented
            ? [.environmentPrimary(chatIDHint: fallback.chatIDHint)]
            : [])
            + administrators
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Label("How to connect an account", systemImage: "link.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Theme.ink)

                    instruction(number: 1, text: "Ask the person to privately message \(TelegramSupportAdminWebsiteRoute.identityCommand) to the parent-support bot.")
                    instruction(number: 2, text: "Enter the name and numeric chat ID returned by the bot.")
                    instruction(number: 3, text: "After saving, ask them to send /start, then use Send Test to confirm delivery.")
                }
                .padding(.vertical, 5)
            }

            Section {
                NavigationLink {
                    AddTelegramSupportAdministratorView {
                        await loadAdministrators(reportFailure: false)
                    }
                } label: {
                    Label("Add Telegram Administrator", systemImage: "person.badge.plus")
                }
                .disabled(loading || loadFailed)
            }

            Section {
                if loading && allAdministrators.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Loading Telegram administrators…")
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if loadFailed && allAdministrators.isEmpty {
                    ContentUnavailableView {
                        Label("Could Not Load Administrators", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text("Refresh the list before making administrator changes.")
                    } actions: {
                        Button("Try Again") {
                            Task { await loadAdministrators() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if allAdministrators.isEmpty {
                    ContentUnavailableView(
                        "No Administrators Configured",
                        systemImage: "person.2.slash",
                        description: Text("Use Add Telegram Administrator to connect another recipient.")
                    )
                } else {
                    if loadFailed {
                        Label(
                            "This list may be out of date. Refresh it before making another change.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(Theme.amber)
                    }
                    ForEach(allAdministrators) { administrator in
                        administratorRow(administrator)
                    }
                }
            } header: {
                HStack {
                    Text("All Administrators")
                    Spacer()
                    if !allAdministrators.isEmpty {
                        Text("\(effectiveActiveCount) active")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    DataRefreshButton(scope: "Telegram administrators") {
                        await loadAdministrators()
                    }
                }
            } footer: {
                if fallback.configured {
                    Text("The Primary Administrator is configured in Vercel and cannot be paused or removed here. Website roles are managed separately.")
                } else {
                    Text("Telegram IDs are masked. Website and app access roles are managed separately.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Telegram Administrators")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadAdministrators()
        }
        .alert(
            "Remove Telegram Administrator?",
            isPresented: $showRemovalConfirmation,
            presenting: pendingRemoval
        ) { administrator in
            Button("Remove", role: .destructive) {
                Task { await remove(administrator) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { administrator in
            Text("\(administrator.displayName) will stop receiving parent-support notifications.")
        }
    }

    @ViewBuilder
    private func administratorRow(_ administrator: TelegramSupportAdministrator) -> some View {
        HStack(spacing: 12) {
            Image(systemName: administrator.deploymentFallback ? "checkmark.shield.fill" : "paperplane.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(
                    administrator.deploymentFallback ? Theme.green : Theme.blue,
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(administrator.displayName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                Text(administrator.maskedChatID)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 8)

            StatusBadge(
                text: administrator.deploymentFallback
                    ? "Primary"
                    : (administrator.active ? "Active" : "Paused"),
                color: administrator.active ? Theme.green : Theme.secondaryText
            )

            if administrator.managedRecord {
                Menu {
                    if administrator.active {
                        Button {
                            Task { await sendTest(to: administrator) }
                        } label: {
                            Label("Send Test", systemImage: "paperplane")
                        }
                    }

                    if !administrator.deploymentFallback {
                        Button {
                            Task { await setActive(!administrator.active, for: administrator) }
                        } label: {
                            Label(
                                administrator.active ? "Pause Notifications" : "Enable Notifications",
                                systemImage: administrator.active ? "bell.slash" : "bell"
                            )
                        }

                        Button(role: .destructive) {
                            pendingRemoval = administrator
                            showRemovalConfirmation = true
                        } label: {
                            Label("Remove Administrator", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 38, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(loading || loadFailed)
                .accessibilityLabel("Actions for \(administrator.displayName)")
            }
        }
        .padding(.vertical, 3)
    }

    private func instruction(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Theme.blue, in: Circle())
            Text(text)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @discardableResult
    private func loadAdministrators(reportFailure: Bool = true) async -> Bool {
        guard state.role == .superuser, !loading else { return false }
        loading = true
        defer { loading = false }

#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTestingTelegramAdministrators") {
            fallback = TelegramSupportFallback(values: [
                "configured": .bool(true),
                "represented": .bool(false),
                "chat_id_hint": .string("••••••3766")
            ])
            effectiveActiveCount = 2
            administrators = [
                TelegramSupportAdministrator(values: [
                    "id": .string("ui-test-added-administrator"),
                    "display_name": .string("Weekend Support Admin"),
                    "chat_id_hint": .string("•••••6789"),
                    "active": .bool(true),
                    "deployment_fallback": .bool(false)
                ])
            ].compactMap { $0 }
            loadFailed = false
            return true
        }
#endif

        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: TelegramSupportAdminWebsiteRoute.administrators
            )
            let object = response.object ?? [:]
            administrators = object["admins"]?.array?
                .compactMap(\.object)
                .compactMap(TelegramSupportAdministrator.init(values:))
                .sorted {
                    if $0.active != $1.active { return $0.active && !$1.active }
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                } ?? []
            fallback = TelegramSupportFallback(values: object["fallback"]?.object ?? [:])
            effectiveActiveCount = Int(object["effective_active_count"]?.double ?? 0)
            loadFailed = false
            return true
        } catch {
            loadFailed = true
            if reportFailure { state.show(error) }
            return false
        }
    }

    private func setActive(
        _ active: Bool,
        for administrator: TelegramSupportAdministrator
    ) async {
        guard state.role == .superuser else {
            state.show("Superuser access is required.", kind: .error)
            return
        }
        let activity = state.beginActivity(
            active ? "Enabling Telegram administrator…" : "Pausing Telegram administrator…"
        )
        defer { state.endActivity(activity) }

        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: TelegramSupportAdminWebsiteRoute.administrators,
                method: "PATCH",
                body: [
                    "id": .string(administrator.id),
                    "active": .bool(active)
                ]
            )
            let refreshed = await loadAdministrators(reportFailure: false)
            if refreshed {
                state.show("\(administrator.displayName) was \(active ? "enabled" : "paused").")
            } else {
                state.show(
                    "The change was saved, but the administrator list could not refresh. Try again before making another change.",
                    kind: .error
                )
            }
        } catch {
            state.show(error)
        }
    }

    private func sendTest(to administrator: TelegramSupportAdministrator) async {
        guard state.role == .superuser else {
            state.show("Superuser access is required.", kind: .error)
            return
        }
        let activity = state.beginActivity("Sending Telegram test…")
        defer { state.endActivity(activity) }

        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: TelegramSupportAdminWebsiteRoute.test,
                method: "POST",
                body: ["id": .string(administrator.id)]
            )
            state.show("Test notification sent to \(administrator.displayName).")
        } catch {
            state.show(error)
        }
    }

    private func remove(_ administrator: TelegramSupportAdministrator) async {
        guard state.role == .superuser else {
            state.show("Superuser access is required.", kind: .error)
            return
        }
        let activity = state.beginActivity("Removing Telegram administrator…")
        defer { state.endActivity(activity) }

        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: TelegramSupportAdminWebsiteRoute.administrators,
                method: "DELETE",
                body: ["id": .string(administrator.id)]
            )
            pendingRemoval = nil
            let refreshed = await loadAdministrators(reportFailure: false)
            if refreshed {
                state.show("\(administrator.displayName) was removed.")
            } else {
                state.show(
                    "The account was removed, but the administrator list could not refresh. Try again before making another change.",
                    kind: .error
                )
            }
        } catch {
            state.show(error)
        }
    }
}

private struct AddTelegramSupportAdministratorView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let onAdded: () async -> Bool

    @State private var displayName = ""
    @State private var chatID = ""
    @State private var errorMessage = ""

    private var normalizedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedChatID: String {
        chatID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var validChatID: Bool {
        isValidTelegramSupportChatID(normalizedChatID)
    }

    private var canSubmit: Bool {
        !normalizedName.isEmpty && normalizedName.count <= 80 && validChatID
    }

    var body: some View {
        Form {
            Section {
                Label {
                    Text("The person must privately send \(TelegramSupportAdminWebsiteRoute.identityCommand) to the parent-support bot before you add them.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                } icon: {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(Theme.blue)
                }
            }

            Section("Administrator") {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)

                TextField("Telegram chat ID", text: $chatID)
                    .keyboardType(.numberPad)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if !errorMessage.isEmpty {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.red)
                }
            }

            Section {
                AsyncActionButton(
                    title: "Add Telegram Administrator",
                    progressTitle: "Adding administrator…",
                    icon: "person.badge.plus",
                    disabled: !canSubmit
                ) {
                    await addAdministrator()
                }
            } footer: {
                Text("After adding the account, ask the person to send /start and use Send Test from the administrator list.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Add Administrator")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addAdministrator() async {
        guard state.role == .superuser else {
            errorMessage = "Superuser access is required."
            return
        }

        errorMessage = ""
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: TelegramSupportAdminWebsiteRoute.administrators,
                method: "POST",
                body: [
                    "display_name": .string(normalizedName),
                    "telegram_chat_id": .string(normalizedChatID)
                ]
            )
            let refreshed = await onAdded()
            if refreshed {
                state.show("\(normalizedName) was added. Ask them to send /start, then use Send Test.")
            } else {
                state.show(
                    "\(normalizedName) was added, but the administrator list could not refresh. Try again before making another change.",
                    kind: .error
                )
            }
            dismiss()
        } catch {
            guard !error.isExpectedCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }
}

private struct ManagedUserRow: View {
    let user: DynamicRecord

    private var name: String {
        user.values["user_metadata"]?.object?.text(
            "name",
            fallback: user.values.text("email", fallback: "User")
        ) ?? "User"
    }

    private var role: UserRole {
        if let value = user.values["app_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }
        if let value = user.values["user_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }
        return .member
    }

    private var avatarURL: URL? {
        URL(string: user.values["user_metadata"]?.object?.text("avatar_url") ?? "")
    }

    var body: some View {
        HStack(spacing: 11) {
            AvatarView(url: avatarURL, name: name, size: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                Text(user.values.text("email"))
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            StatusBadge(text: role.displayName, color: Theme.colour(for: role))
        }
        .padding(.vertical, 2)
    }
}

private struct ManagedUserDetailView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    let user: DynamicRecord
    let callerRole: UserRole
    let currentUserID: String?
    let onChanged: () async -> Void

    @State private var selectedRole: UserRole
    @State private var savedRole: UserRole
    @State private var telegramHandle: String
    @State private var showDeleteConfirmation = false

    init(
        user: DynamicRecord,
        telegramHandle: String,
        callerRole: UserRole,
        currentUserID: String?,
        onChanged: @escaping () async -> Void
    ) {
        self.user = user
        self.callerRole = callerRole
        self.currentUserID = currentUserID
        self.onChanged = onChanged
        let initialRole = Self.role(for: user)
        _selectedRole = State(initialValue: initialRole)
        _savedRole = State(initialValue: initialRole)
        _telegramHandle = State(initialValue: telegramHandle)
    }

    private var name: String {
        user.values["user_metadata"]?.object?.text(
            "name",
            fallback: user.values.text("email", fallback: "User")
        ) ?? "User"
    }

    private var isCurrentUser: Bool {
        user.id == currentUserID
    }

    private var canDelete: Bool {
        !isCurrentUser && (callerRole == .superuser || savedRole == .member)
    }

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Name", value: name)
                LabeledContent("Email", value: user.values.text("email"))
                LabeledContent("User ID", value: user.id)
                    .font(.caption)
                    .textSelection(.enabled)
            }

            if callerRole == .superuser {
                Section {
                    Picker("Role", selection: $selectedRole) {
                        ForEach(UserRole.allCases, id: \.self) { role in
                            Text(role.displayName).tag(role)
                        }
                    }
                    .disabled(isCurrentUser)

                    AsyncActionButton(
                        title: "Save Role",
                        progressTitle: "Updating role…",
                        icon: "checkmark.shield",
                        disabled: isCurrentUser || selectedRole == savedRole
                    ) {
                        await saveRole()
                    }
                } header: {
                    Text("Access Role")
                } footer: {
                    Text(
                        isCurrentUser
                            ? "You cannot change your own role."
                            : "This controls which app operations the account can access."
                    )
                }
            }

            Section {
                TextField("@telegram_username", text: $telegramHandle)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                AsyncActionButton(
                    title: "Save Telegram Handle",
                    progressTitle: "Saving Telegram link…",
                    icon: "paperplane.fill",
                    disabled: normalizedHandle.isEmpty
                ) {
                    await saveTelegramHandle()
                }
            } header: {
                Text("Coach Telegram Link")
            } footer: {
                Text("Used to associate coaching attendance and Telegram notifications with this account.")
            }

            Section("Password Assistance") {
                AsyncActionButton(
                    title: "Send Password Reset Code",
                    progressTitle: "Sending reset code…",
                    icon: "envelope.badge"
                ) {
                    await resendResetCode()
                }
            }

            if canDelete {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete User Account", systemImage: "person.crop.circle.badge.minus")
                    }
                } footer: {
                    Text("This permanently removes the account and cannot be undone.")
                }
            }
        }
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Delete \(name)?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete Account", role: .destructive) {
                Task { await deleteUser() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The user will immediately lose access to PatLau.")
        }
    }

    private var normalizedHandle: String {
        let trimmed = telegramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed.hasPrefix("@") ? trimmed : "@\(trimmed)"
    }

    private func saveRole() async {
        let activity = state.beginActivity("Updating user access role…")
        defer { state.endActivity(activity) }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: "/api/users/update",
                method: "POST",
                body: [
                    "userId": .string(user.id),
                    "role": .string(selectedRole.rawValue)
                ]
            )
            savedRole = selectedRole
            await onChanged()
            state.show("Role updated for \(name).")
        } catch {
            state.show(error)
        }
    }

    private func saveTelegramHandle() async {
        let activity = state.beginActivity("Saving Telegram account link…")
        defer { state.endActivity(activity) }
        do {
            _ = try await BackendClient.shared.upsert(
                table: "coach_profiles",
                values: [
                    "auth_user_id": .string(user.id),
                    "telegram_handle": .string(normalizedHandle),
                    "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                ],
                onConflict: "auth_user_id"
            )
            telegramHandle = normalizedHandle
            await onChanged()
            state.show("Telegram handle linked for \(name).")
        } catch {
            state.show(error)
        }
    }

    private func resendResetCode() async {
        let activity = state.beginActivity("Sending password reset code…")
        defer { state.endActivity(activity) }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: "/api/users/resend-reset-code",
                method: "POST",
                body: ["email": .string(user.values.text("email"))]
            )
            state.show("Password reset code sent to \(user.values.text("email")).")
        } catch {
            state.show(error)
        }
    }

    private func deleteUser() async {
        let activity = state.beginActivity("Deleting user account…")
        defer { state.endActivity(activity) }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: "/api/users/delete",
                method: "POST",
                body: ["userId": .string(user.id)]
            )
            await onChanged()
            state.show("\(name) was deleted.")
            dismiss()
        } catch {
            state.show(error)
        }
    }

    private static func role(for user: DynamicRecord) -> UserRole {
        if let value = user.values["app_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }
        if let value = user.values["user_metadata"]?.object?["role"]?.string,
           let role = UserRole(rawValue: value) {
            return role
        }
        return .member
    }
}

private struct AddManagedUserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    let callerRole: UserRole
    let onSaved: () async -> Void

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var role: UserRole = .member
    @State private var telegramHandle = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(title: "Add User", onCancel: { dismiss() })
                Form {
                Section("Account Details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Temporary password (optional)", text: $password)
                        .textContentType(.newPassword)
                }

                if callerRole == .superuser {
                    Section("Access") {
                        Picker("Role", selection: $role) {
                            ForEach(UserRole.allCases, id: \.self) { role in
                                Text(role.displayName).tag(role)
                            }
                        }
                    }
                } else {
                    Section("Access") {
                        LabeledContent("Role", value: UserRole.member.displayName)
                    }
                }

                Section {
                    TextField("@telegram_username (optional)", text: $telegramHandle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Coach Telegram Link")
                } footer: {
                    Text("Leave this blank for parent or non-coaching accounts.")
                }

                Section {
                    AsyncActionButton(
                        title: "Create User",
                        progressTitle: "Creating user…",
                        icon: "person.badge.plus",
                        disabled: normalizedName.isEmpty
                            || normalizedEmail.isEmpty
                            || (!password.isEmpty && password.count < 8)
                    ) {
                        await createUser()
                    }
                } footer: {
                    Text(
                        password.isEmpty
                            ? "A password setup email will be sent to the new account."
                            : "Temporary passwords must contain at least eight characters."
                    )
                }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private var normalizedHandle: String {
        let value = telegramHandle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return value.hasPrefix("@") ? value : "@\(value)"
    }

    private func createUser() async {
        let accountRole = callerRole == .admin ? UserRole.member : role

        var body: JSONObject = [
            "email": .string(normalizedEmail),
            "name": .string(normalizedName),
            "role": .string(accountRole.rawValue)
        ]
        if !password.isEmpty {
            body["password"] = .string(password)
        }

        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "/api/users/create",
                method: "POST",
                body: body
            )

            let createdUserID = response.object?["user"]?.object?.text("id")
            if let createdUserID, !normalizedHandle.isEmpty {
                _ = try await BackendClient.shared.upsert(
                    table: "coach_profiles",
                    values: [
                        "auth_user_id": .string(createdUserID),
                        "telegram_handle": .string(normalizedHandle),
                        "updated_at": .string(ISO8601DateFormatter().string(from: Date()))
                    ],
                    onConflict: "auth_user_id"
                )
            }

            await onSaved()
            state.show("User \(normalizedName) created.")
            dismiss()
        } catch {
            state.show(error)
        }
    }
}

private struct AvatarView: View {
    let url: URL?
    let name: String
    var size: CGFloat = 82
    var localImage: UIImage? = nil

    var body: some View {
        Group {
            if let localImage {
                Image(uiImage: localImage)
                    .resizable()
                    .scaledToFill()
            } else {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            LinearGradient(
                                colors: [Theme.blue, Theme.blueDark],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            Text(String(name.prefix(1)).uppercased())
                                .font(.system(size: size * 0.4, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(.white, lineWidth: 2))
        .shadow(color: Theme.blue.opacity(0.15), radius: 8, y: 3)
    }
}

private struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(
        _ uiViewController: UIImagePickerController,
        context: Context
    ) {}

    final class Coordinator: NSObject,
        UIImagePickerControllerDelegate,
        UINavigationControllerDelegate {

        let onImage: (UIImage) -> Void
        let onCancel: () -> Void

        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

private struct PhotoCropper: View {
    @Environment(\.dismiss) private var dismiss

    let image: UIImage
    let onSave: (Data) async throws -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var scaleStart: CGFloat = 1
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let preview: CGFloat = 300

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Adjust Photo",
                    onCancel: { if !isSaving { dismiss() } }
                )

                VStack(spacing: 20) {
                    ZStack {
                    Color(uiColor: .systemGray6)
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(scale)
                        .offset(offset)
                }
                .frame(width: preview, height: preview)
                .clipShape(Circle())
                .overlay(Circle().stroke(.white, lineWidth: 4))
                .shadow(radius: 10)
                .contentShape(Circle())
                .gesture(
                    DragGesture()
                        .onChanged {
                            offset = CGSize(
                                width: dragStart.width + $0.translation.width,
                                height: dragStart.height + $0.translation.height
                            )
                        }
                        .onEnded { _ in dragStart = offset }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged {
                            scale = min(max(scaleStart * $0, 0.65), 4)
                        }
                        .onEnded { _ in scaleStart = scale }
                )

                Text("Drag to reposition the image and pinch to zoom.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .multilineTextAlignment(.center)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                HStack(spacing: 10) {
                    Button {
                        scale = max(0.65, scale - 0.1)
                        scaleStart = scale
                    } label: {
                        Label("Zoom Out", systemImage: "minus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        scale = min(4, scale + 0.1)
                        scaleStart = scale
                    } label: {
                        Label("Zoom In", systemImage: "plus.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                }

                Button {
                    if let data = renderedJPEG() {
                        errorMessage = nil
                        isSaving = true
                        Task {
                            do {
                                try await onSave(data)
                                isSaving = false
                                dismiss()
                            } catch {
                                errorMessage = error.localizedDescription
                                isSaving = false
                            }
                        }
                    } else {
                        errorMessage = "The adjusted photo could not be prepared. Please try again."
                    }
                } label: {
                    Label(
                        isSaving ? "Updating profile photo…" : "Use This Photo",
                        systemImage: isSaving ? "arrow.triangle.2.circlepath" : "checkmark"
                    )
                        .frame(maxWidth: .infinity)
                        .touchTarget()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)

                    Spacer()
                }
                .padding(20)
            }
            .toolbar(.hidden, for: .navigationBar)
            .overlay {
                if isSaving {
                    LoadingOverlay(text: "Updating profile photo")
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
    }

    private func renderedJPEG() -> Data? {
        let output: CGFloat = 768
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: output, height: output)
        )
        let result = renderer.image { context in
            context.cgContext.setFillColor(UIColor.systemGray6.cgColor)
            context.cgContext.fill(
                CGRect(x: 0, y: 0, width: output, height: output)
            )

            let fit = min(output / image.size.width, output / image.size.height) * scale
            let size = CGSize(
                width: image.size.width * fit,
                height: image.size.height * fit
            )
            let ratio = output / preview
            image.draw(
                in: CGRect(
                    x: (output - size.width) / 2 + offset.width * ratio,
                    y: (output - size.height) / 2 + offset.height * ratio,
                    width: size.width,
                    height: size.height
                )
            )
        }
        return result.jpegData(compressionQuality: 0.88)
    }
}
