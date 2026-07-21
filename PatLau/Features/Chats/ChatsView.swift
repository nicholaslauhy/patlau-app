import SwiftUI
import UIKit

private let supportStatuses = [
    "ai_active", "waiting_parent", "escalated",
    "human_active", "resolved", "closed_parent"
]

enum SupportWebsiteRoute {
    static let summary = "/api/support"
}

enum SupportRefreshSection: String, CaseIterable {
    case inbox = "Inbox"
    case knowledge = "Knowledge"
    case announcements = "Announcements"

    var label: String {
        switch self {
        case .inbox: "parent support inbox"
        case .knowledge: "support knowledge"
        case .announcements: "support announcements"
        }
    }

    var resources: Set<String> {
        switch self {
        case .inbox: ["support_conversations", "support_contacts"]
        case .knowledge: ["support_knowledge"]
        case .announcements: ["support_announcements"]
        }
    }

    var responseKey: String {
        switch self {
        case .inbox: "conversations"
        case .knowledge: "knowledge"
        case .announcements: "announcements"
        }
    }
}

private func supportStatusLabel(_ value: String) -> String {
    switch value {
    case "ai_active": "AI active"
    case "waiting_parent": "Waiting for parent"
    case "escalated": "Escalated"
    case "human_active": "Human active"
    case "resolved": "Resolved"
    case "closed_parent": "Closed by parent"
    default: value.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

private func supportStatusColor(_ value: String) -> Color {
    switch value {
    case "escalated": Theme.red
    case "human_active": Theme.amber
    case "resolved": Theme.green
    case "closed_parent": Theme.secondaryText
    default: Theme.blue
    }
}

private func supportContactName(_ record: DynamicRecord) -> String {
    let direct = record.values.text("parent_name")
    if !direct.isEmpty { return direct }
    if let contact = record.values["contact"]?.object {
        let name = [contact.text("first_name"), contact.text("last_name")]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !name.isEmpty { return name }
        let username = contact.text("username")
        if !username.isEmpty { return "@\(username)" }
    }
    return "Telegram parent"
}

private func flattenSupportConversation(_ object: JSONObject) -> DynamicRecord {
    var value = object
    if let contact = object["contact"]?.object {
        value["parent_name"] = .string(
            [contact.text("first_name"), contact.text("last_name")]
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        )
        value["username"] = .string(contact.text("username"))
        value["contact_blocked"] = .bool(contact.flag("blocked"))
    }
    return DynamicRecord(values: value)
}

private func appDateTime(_ value: String) -> String {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = fractional.date(from: value)
            ?? ISO8601DateFormatter().date(from: value) else { return value }
    return date.formatted(
        .dateTime
            .day()
            .month(.abbreviated)
            .year()
            .hour()
            .minute()
    )
}

struct ChatsView: View {
    @EnvironmentObject private var state: AppState

    @State private var tab = "Inbox"
    @State private var conversations: [DynamicRecord] = []
    @State private var knowledge: [DynamicRecord] = []
    @State private var announcements: [DynamicRecord] = []
    @State private var search = ""
    @State private var statusFilter = "all"
    @State private var loading = false
    @State private var editor: SupportEditorKind?
    @State private var pendingDelete: SupportDeleteRequest?

    private var filteredRecords: [DynamicRecord] {
        currentRecords.filter { record in
            guard record.matches(search) else { return false }
            return tab != "Inbox"
                || statusFilter == "all"
                || record.values.text("status") == statusFilter
        }
    }

    private var currentSection: SupportRefreshSection {
        SupportRefreshSection(rawValue: tab) ?? .inbox
    }

    private var currentRecords: [DynamicRecord] {
        switch currentSection {
        case .inbox: conversations
        case .knowledge: knowledge
        case .announcements: announcements
        }
    }

    private var escalatedCount: Int {
        conversations.filter { $0.values.text("status") == "escalated" }.count
    }

    private var humanCount: Int {
        conversations.filter { $0.values.text("status") == "human_active" }.count
    }

    private var unreadCount: Int {
        conversations.reduce(0) { $0 + Int($1.values.number("unread_count")) }
    }

    var body: some View {
        Group {
            if state.role != .superuser {
                ContentUnavailableView(
                    "Superuser Access Required",
                    systemImage: "lock.shield",
                    description: Text("Parent chats contain private support conversations.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        introduction
                        conversationMetrics
                        HStack {
                            Text("\(filteredRecords.count) \(chatRecordLabel)")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            DataRefreshButton(scope: currentSection.label) {
                                await load()
                            }
                        }
                        FilterChips(
                            values: ["Inbox", "Knowledge", "Announcements"],
                            selection: $tab
                        )

                        AppSearchField(prompt: searchPrompt, text: $search)

                        if tab == "Inbox" {
                            statusMenu
                        } else {
                            Button {
                                editor = tab == "Knowledge"
                                    ? .knowledge(nil)
                                    : .announcement(nil)
                            } label: {
                                Label(
                                    "Add \(tab == "Knowledge" ? "Knowledge" : "Announcement")",
                                    systemImage: "plus"
                                )
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(AppSecondaryButtonStyle())
                            .tint(Theme.teal)
                        }

                        content
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Theme.background)
            }
        }
        .navigationTitle("Chats")
        .task(id: tab) { await load() }
        .refreshable { await load() }
        .sheet(item: $editor) { kind in
            SupportEditorSheet(kind: kind) { await load() }
        }
        .alert(item: $pendingDelete) { request in
            Alert(
                title: Text("Delete \(request.kind.title)?"),
                message: Text("“\(request.record.values.text("title", fallback: "This record"))” will be permanently removed."),
                primaryButton: .destructive(Text("Delete")) {
                    Task { await delete(request) }
                },
                secondaryButton: .cancel()
            )
        }
        .overlay {
            if loading {
                LoadingOverlay(text: "Loading parent support")
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Telegram parent support", systemImage: "bubble.left.and.bubble.right.fill")
                .font(.headline)
                .foregroundStyle(Theme.teal)
            Text("Review AI replies, take over escalated conversations and keep parent information current.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var conversationMetrics: some View {
        HStack(spacing: 0) {
            supportMetric("Escalated", value: escalatedCount, color: Theme.red)
            Divider().frame(height: 42)
            supportMetric("Human active", value: humanCount, color: Theme.amber)
            Divider().frame(height: 42)
            supportMetric("Unread", value: unreadCount, color: Theme.blue)
        }
        .appCard(padding: 12)
    }

    private func supportMetric(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    private var statusMenu: some View {
        HStack {
            Label("Conversation status", systemImage: "line.3.horizontal.decrease")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.ink)
            Spacer()
            Menu {
                Button("All statuses") { statusFilter = "all" }
                ForEach(supportStatuses, id: \.self) { value in
                    Button(supportStatusLabel(value)) { statusFilter = value }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(statusFilter == "all" ? "All statuses" : supportStatusLabel(statusFilter))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                }
                .foregroundStyle(Theme.teal)
            }
            .buttonStyle(.plain)
        }
        .appCard(padding: 14)
    }

    private var searchPrompt: String {
        switch tab {
        case "Knowledge": "Search title, information, category or status"
        case "Announcements": "Search title, announcement, programme or status"
        default: "Search parents or messages"
        }
    }

    private var chatRecordLabel: String {
        let singular: String
        switch tab {
        case "Knowledge": singular = "knowledge record"
        case "Announcements": singular = "announcement"
        default: singular = "conversation"
        }
        return "\(singular)\(filteredRecords.count == 1 ? "" : "s")"
    }

    @ViewBuilder
    private var content: some View {
        if filteredRecords.isEmpty && !loading {
            EmptyState(
                icon: tab == "Inbox" ? "bubble.left.and.bubble.right" : "doc.text.magnifyingglass",
                title: "Nothing found",
                message: search.isEmpty
                    ? "No records are available yet."
                    : "Try another search term or filter."
            )
        } else {
            ForEach(filteredRecords) { record in
                if tab == "Inbox" {
                    NavigationLink {
                        ConversationView(conversation: record)
                    } label: {
                        ConversationRow(conversation: record, query: search)
                    }
                    .buttonStyle(.plain)
                } else {
                    SupportRecordCard(
                        record: record,
                        kind: tab == "Knowledge" ? .knowledge : .announcement,
                        query: search,
                        onEdit: {
                            editor = tab == "Knowledge"
                                ? .knowledge(record)
                                : .announcement(record)
                        },
                        onDelete: {
                            pendingDelete = SupportDeleteRequest(
                                record: record,
                                kind: tab == "Knowledge" ? .knowledge : .announcement
                            )
                        }
                    )
                }
            }
        }
    }

    private func load() async {
        guard state.role == .superuser else { return }
        loading = currentRecords.isEmpty
        defer { loading = false }
        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: SupportWebsiteRoute.summary
            )
            guard let records = response.object?[currentSection.responseKey]?.array else {
                throw BackendError.message(
                    "The parent-support service returned an invalid \(tab.lowercased()) response."
                )
            }
            let decoded = records.compactMap(\.object).map(DynamicRecord.init(values:))
            switch currentSection {
            case .inbox:
                conversations = decoded.map {
                    flattenSupportConversation($0.values)
                }
            case .knowledge:
                knowledge = decoded
            case .announcements:
                announcements = decoded
            }
        } catch {
            state.show(error)
        }
    }

    private func delete(_ request: SupportDeleteRequest) async {
        let activity = state.beginActivity("Deleting \(request.kind.title.lowercased())…")
        defer { state.endActivity(activity) }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: SupportWebsiteRoute.summary,
                method: "POST",
                body: [
                    "action": .string(request.kind == .knowledge ? "delete_knowledge" : "delete_announcement"),
                    "id": .string(request.record.id)
                ]
            )
            state.show("\(request.kind.title) deleted.")
            await load()
        } catch {
            state.show(error.localizedDescription, kind: .error)
        }
    }
}

private struct ConversationRow: View {
    let conversation: DynamicRecord
    let query: String

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(String(supportContactName(conversation).prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(Theme.teal)
                .frame(width: 42, height: 42)
                .background(Theme.teal.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    SearchHighlight(text: supportContactName(conversation), query: query)
                        .font(.headline)
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 8)
                    Text(appDateTime(conversation.values.text("last_message_at")))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }

                StatusBadge(
                    text: supportStatusLabel(conversation.values.text("status")),
                    color: supportStatusColor(conversation.values.text("status"))
                )

                SearchHighlight(
                    text: conversation.values.text("last_message_preview", fallback: "Conversation started"),
                    query: query
                )
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
            }

            if conversation.values.number("unread_count") > 0 {
                Text("\(Int(conversation.values.number("unread_count")))")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .frame(minWidth: 24, minHeight: 24)
                    .background(Theme.red, in: Circle())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 12)
            }
        }
        .appCard()
    }
}

private enum SupportRecordKind {
    case knowledge
    case announcement

    var title: String {
        self == .knowledge ? "Knowledge" : "Announcement"
    }
}

private struct SupportDeleteRequest: Identifiable {
    let id = UUID()
    let record: DynamicRecord
    let kind: SupportRecordKind
}

private struct SupportRecordCard: View {
    let record: DynamicRecord
    let kind: SupportRecordKind
    let query: String
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    StatusBadge(
                        text: record.values.text("status", fallback: "draft"),
                        color: supportRecordStatusColor
                    )
                    Text(kind == .knowledge
                         ? record.values.text("category", fallback: "General")
                         : record.values.text("programme", fallback: "all").capitalized)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Menu {
                    Button("Edit", systemImage: "pencil", action: onEdit)
                    Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Actions for \(record.values.text("title"))")
            }

            SearchHighlight(text: record.values.text("title", fallback: "Untitled"), query: query)
                .font(.headline)
                .foregroundStyle(Theme.ink)

            SearchHighlight(text: record.values.text("content"), query: query)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(5)

            if kind == .announcement {
                Label(
                    "\(record.values.text("starts_on")) – \(record.values.text("ends_on"))",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            } else if !record.values.text("updated_at").isEmpty {
                Text("Updated \(appDateTime(record.values.text("updated_at")))")
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .appCard()
    }

    private var supportRecordStatusColor: Color {
        switch record.values.text("status") {
        case "published": Theme.green
        case "archived": Theme.secondaryText
        default: Theme.amber
        }
    }
}

private enum SupportEditorKind: Identifiable {
    case knowledge(DynamicRecord?)
    case announcement(DynamicRecord?)

    var id: String {
        switch self {
        case .knowledge(let record): "knowledge-\(record?.id ?? "new")"
        case .announcement(let record): "announcement-\(record?.id ?? "new")"
        }
    }
}

private struct SupportEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    let kind: SupportEditorKind
    let onSaved: () async -> Void

    @State private var title = ""
    @State private var category = "General"
    @State private var content = ""
    @State private var status = "draft"
    @State private var programme = "all"
    @State private var startsOn = Date()
    @State private var endsOn = Date()
    @State private var saving = false
    @State private var errorMessage: String?

    private var isKnowledge: Bool {
        if case .knowledge = kind { true } else { false }
    }

    private var record: DynamicRecord? {
        switch kind {
        case .knowledge(let value), .announcement(let value): value
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: record == nil
                        ? "Add \(isKnowledge ? "Knowledge" : "Announcement")"
                        : "Edit \(isKnowledge ? "Knowledge" : "Announcement")",
                    cancelDisabled: saving,
                    onCancel: { dismiss() }
                )

                Form {
                    Section {
                        TextField("Title", text: $title)
                        if isKnowledge {
                            TextField("Category", text: $category)
                        } else {
                            Picker("Programme", selection: $programme) {
                                Text("All programmes").tag("all")
                                Text("Weekend").tag("weekend")
                                Text("Weekday").tag("weekday")
                                Text("MatchPlay").tag("matchplay")
                                Text("1-1").tag("1-1")
                            }
                            DatePicker("Starts on", selection: $startsOn, displayedComponents: .date)
                            DatePicker("Ends on", selection: $endsOn, in: startsOn..., displayedComponents: .date)
                        }
                    } header: {
                        Text(isKnowledge ? "Chatbot knowledge" : "Time-sensitive information")
                    } footer: {
                        Text(isKnowledge
                             ? "Published information can be used immediately in parent answers."
                             : "Active published announcements override general knowledge.")
                    }

                    Section(isKnowledge ? "Information" : "Announcement") {
                        TextEditor(text: $content)
                            .frame(minHeight: 180)
                    }

                    Section("Publishing") {
                        Picker("Status", selection: $status) {
                            Text("Draft").tag("draft")
                            Text("Published").tag("published")
                            Text("Archived").tag("archived")
                        }
                    }

                    Section {
                        AsyncActionButton(
                            title: "Save \(isKnowledge ? "Knowledge" : "Announcement")",
                            progressTitle: "Saving…",
                            icon: "checkmark",
                            disabled: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || saving
                        ) {
                            await save()
                        }
                        .tint(Theme.teal)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear { populate() }
            .alert("Unable to Save", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "The support record could not be saved.")
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(saving)
    }

    private func populate() {
        guard let record else { return }
        title = record.values.text("title")
        content = record.values.text("content")
        status = record.values.text("status", fallback: "draft")
        category = record.values.text("category", fallback: "General")
        programme = record.values.text("programme", fallback: "all")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        if let value = formatter.date(from: record.values.text("starts_on")) { startsOn = value }
        if let value = formatter.date(from: record.values.text("ends_on")) { endsOn = value }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        var body: JSONObject = [
            "action": .string(isKnowledge ? "save_knowledge" : "save_announcement"),
            "title": .string(title.trimmingCharacters(in: .whitespacesAndNewlines)),
            "content": .string(content.trimmingCharacters(in: .whitespacesAndNewlines)),
            "status": .string(status)
        ]
        if let record { body["id"] = .string(record.id) }
        if isKnowledge {
            body["category"] = .string(category.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            body.merge([
                "programme": .string(programme),
                "startsOn": .string(startsOn.isoDateKey),
                "endsOn": .string(endsOn.isoDateKey)
            ]) { _, new in new }
        }

        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: SupportWebsiteRoute.summary,
                method: "POST",
                body: body
            )
            await onSaved()
            dismiss()
            state.show("\(isKnowledge ? "Knowledge" : "Announcement") saved.")
        } catch {
            if !error.isExpectedCancellation {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ConversationView: View {
    @EnvironmentObject private var state: AppState

    let conversation: DynamicRecord

    @State private var details: DynamicRecord?
    @State private var messages: [DynamicRecord] = []
    @State private var reply = ""
    @State private var loading = false
    @State private var busy = false
    @State private var errorMessage: String?

    private var activeConversation: DynamicRecord { details ?? conversation }
    private var contact: JSONObject { activeConversation.values["contact"]?.object ?? [:] }
    private var blocked: Bool {
        activeConversation.values.flag("contact_blocked") || contact.flag("blocked")
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        conversationHeader
                        conversationActions

                        HStack {
                            Text("\(messages.count) message\(messages.count == 1 ? "" : "s")")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            DataRefreshButton(scope: "conversation messages") {
                                await load()
                            }
                        }

                        if blocked {
                            Label(
                                "This Telegram contact is blocked. Replies cannot be sent.",
                                systemImage: "hand.raised.fill"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .appCard()
                        }

                        if messages.isEmpty && !loading {
                            EmptyState(
                                icon: "bubble.left",
                                title: "No messages yet",
                                message: "The Telegram history will appear here."
                            )
                        } else {
                            ForEach(messages) { message in
                                MessageBubble(
                                    message: message,
                                    parentName: supportContactName(activeConversation)
                                )
                                .id(message.id)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 16)
                }
                .onChange(of: messages.count) { _, _ in
                    if let last = messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }

            Divider()
            replyComposer
        }
        .background(Theme.background)
        .navigationTitle(supportContactName(activeConversation))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .overlay {
            if loading {
                LoadingOverlay(text: "Loading messages")
            }
        }
        .alert("Unable to Complete Chat Action", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The chat action could not be completed.")
        }
    }

    private var conversationHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(supportContactName(activeConversation))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.ink)
                    Text(contact.text("username").isEmpty
                         ? "No Telegram username"
                         : "@\(contact.text("username"))")
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                    if !contact.text("telegram_user_id").isEmpty {
                        Text("Telegram ID \(contact.text("telegram_user_id"))")
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                Spacer()
                StatusBadge(
                    text: supportStatusLabel(activeConversation.values.text("status")),
                    color: supportStatusColor(activeConversation.values.text("status"))
                )
            }

            let reason = activeConversation.values.text("escalation_reason")
            if !reason.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Escalation reason")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.red)
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(Theme.ink)
                }
            }
        }
        .appCard()
    }

    private var conversationActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Conversation control",
                subtitle: activeConversation.values.text("status") == "human_active"
                    ? "AI is paused while you handle this chat."
                    : "Sending a reply automatically takes over this chat."
            )

            HStack(spacing: 16) {
                if activeConversation.values.text("status") != "human_active" {
                    actionButton("Take over", icon: "person.fill.checkmark", color: Theme.amber) {
                        await setStatus("human_active", reason: "Superuser took over the conversation.")
                    }
                }
                if !["ai_active", "waiting_parent"].contains(activeConversation.values.text("status")) {
                    actionButton("Return to AI", icon: "sparkles", color: Theme.blue) {
                        await setStatus("ai_active", reason: "Returned to AI by superuser.")
                    }
                }
                if activeConversation.values.text("status") != "resolved" {
                    actionButton("Resolve", icon: "checkmark.circle", color: Theme.green) {
                        await setStatus("resolved", reason: "Resolved by superuser.")
                    }
                }
            }
        }
        .appCard()
    }

    private func actionButton(
        _ title: String,
        icon: String,
        color: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.headline)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, minHeight: 54)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var replyComposer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Reply through Telegram", text: $reply, axis: .vertical)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.border))
                    .onChange(of: reply) { _, value in
                        if value.count > 3_900 { reply = String(value.prefix(3_900)) }
                    }

                Button {
                    Task { await send() }
                } label: {
                    Group {
                        if busy { ProgressView().tint(.white) }
                        else { Image(systemName: "paperplane.fill") }
                    }
                    .frame(width: 48, height: 48)
                    .foregroundStyle(.white)
                    .background(Theme.teal, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(
                    busy || blocked
                    || reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                .opacity(blocked ? 0.4 : 1)
                .accessibilityLabel("Send reply")
            }

            Text("\(reply.count)/3,900 characters")
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func load() async {
        loading = messages.isEmpty
        defer { loading = false }
        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "\(SupportWebsiteRoute.summary)?conversation_id=\(conversation.id)"
            )
            if let object = response.object?["conversation"]?.object {
                details = flattenSupportConversation(object)
            }
            messages = response.object?["messages"]?.array?
                .compactMap(\.object)
                .map(DynamicRecord.init) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func send() async {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !blocked else {
            errorMessage = "This Telegram contact is blocked."
            return
        }

        busy = true
        defer { busy = false }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: SupportWebsiteRoute.summary,
                method: "POST",
                body: [
                    "action": .string("send_message"),
                    "conversationId": .string(conversation.id),
                    "content": .string(text)
                ]
            )
            reply = ""
            await load()
            state.show("Reply sent to Telegram.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func setStatus(_ status: String, reason: String) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await BackendClient.shared.websiteJSON(
                path: SupportWebsiteRoute.summary,
                method: "POST",
                body: [
                    "action": .string("set_status"),
                    "conversationId": .string(conversation.id),
                    "status": .string(status),
                    "reason": .string(reason)
                ]
            )
            await load()
            state.show("Conversation marked \(supportStatusLabel(status).lowercased()).")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct MessageBubble: View {
    let message: DynamicRecord
    let parentName: String

    private var outbound: Bool {
        let sender = message.values.text("sender_type")
        return sender == "superuser" || sender == "ai" || sender == "system"
            || message.values.text("direction") == "outbound"
    }

    private var senderName: String {
        switch message.values.text("sender_type") {
        case "parent": parentName
        case "superuser": "You"
        case "ai": "AI assistant"
        default: "System"
        }
    }

    var body: some View {
        HStack {
            if outbound { Spacer(minLength: 42) }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(senderName)
                        .font(.caption.weight(.bold))
                    Spacer(minLength: 10)
                    Text(appDateTime(message.values.text("created_at")))
                        .font(.caption2)
                        .opacity(0.8)
                }
                Text(message.values.text("content"))
                    .font(.body)
                    .textSelection(.enabled)

                let sources = message.values["source_refs"]?.array?.compactMap(\.string) ?? []
                if !sources.isEmpty {
                    Text("Sources: \(sources.joined(separator: ", "))")
                        .font(.caption2)
                        .opacity(0.8)
                }
            }
            .foregroundStyle(outbound ? Color.white : Theme.ink)
            .padding(12)
            .background(
                outbound ? Theme.teal : Color(uiColor: .systemGray5),
                in: RoundedRectangle(cornerRadius: 15, style: .continuous)
            )
            if !outbound { Spacer(minLength: 42) }
        }
    }
}

// MARK: - Audit Logs

private let auditCategories = [
    "authentication", "attendance", "payments", "makeup", "students",
    "users", "profiles", "support", "notifications", "coach_attendance", "system"
]

private let auditOutcomes = ["success", "failure", "denied", "accepted", "warning"]

private func auditHumanise(_ value: String) -> String {
    guard !value.isEmpty else { return "Not recorded" }
    return value
        .replacingOccurrences(of: ".", with: " ")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
        .capitalized
}

private func auditCategoryLabel(_ value: String) -> String {
    switch value {
    case "authentication": "Authentication"
    case "users": "User Management"
    case "profiles": "User Profiles"
    case "support": "Chats & Support"
    case "coach_attendance": "Coach Attendance"
    default: auditHumanise(value)
    }
}

private func auditOutcomeLabel(_ value: String) -> String {
    switch value {
    case "success": "Successful"
    case "failure": "Failed"
    case "accepted": "Accepted"
    default: auditHumanise(value)
    }
}

private func auditOutcomeColor(_ value: String) -> Color {
    switch value {
    case "success": Theme.green
    case "failure", "denied": Theme.red
    case "warning": Theme.amber
    default: Theme.blue
    }
}

private func auditCategoryColor(_ value: String) -> Color {
    switch value {
    case "authentication", "users": Theme.purple
    case "payments", "makeup": Theme.amber
    case "support", "notifications": Theme.teal
    case "attendance", "coach_attendance": Theme.green
    case "system": Theme.secondaryText
    default: Theme.blue
    }
}

private func auditActor(_ record: DynamicRecord) -> String {
    for key in ["actor_name", "actor_email", "actor_source"] {
        let value = record.values.text(key)
        if !value.isEmpty { return key == "actor_source" ? auditHumanise(value) : value }
    }
    return "System"
}

private func auditDisplayValue(_ value: JSONValue?) -> String {
    guard let value else { return "—" }
    if let scalar = value.string, !scalar.isEmpty { return scalar }
    if case .null = value { return "—" }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(value),
          let string = String(data: data, encoding: .utf8) else {
        return "—"
    }
    return string
}

struct AuditExportReceipt: Equatable {
    let claimed: Int
    let exported: Int
    let pruned: Int
    let requeued: Int
    let batches: Int
    let exportRunID: String

    init(response: JSONValue) throws {
        guard let envelope = response.object,
              envelope.flag("success"),
              let result = envelope["result"]?.object else {
            throw AuditExportResponseError(
                "The server did not confirm the audit export. No successful delivery should be assumed."
            )
        }

        func requiredCount(_ key: String) throws -> Int {
            guard let value = result[key]?.double,
                  value >= 0,
                  value.rounded() == value else {
                throw AuditExportResponseError(
                    "The audit exporter returned an invalid \(key) count."
                )
            }
            return Int(value)
        }

        claimed = try requiredCount("claimed")
        exported = try requiredCount("exported")
        pruned = try requiredCount("pruned")
        requeued = try requiredCount("requeued")
        batches = try requiredCount("batches")
        exportRunID = result.text("exportRunId")

        guard claimed == exported else {
            throw AuditExportResponseError(
                "Sentry acknowledged \(exported) of \(claimed) claimed audit events. The incomplete batch remains available for retry."
            )
        }
        guard !exportRunID.isEmpty else {
            throw AuditExportResponseError(
                "The website exporter did not return a Sentry run ID. Deploy the tracked Sentry exporter before exporting again."
            )
        }
    }

    var searchQuery: String {
        "audit_export_run_id:\(exportRunID)"
    }
}

struct SentryProbeReceipt: Equatable {
    let probeID: String
    let deliveryBatchID: String

    init(response: JSONValue) throws {
        guard let envelope = response.object,
              let result = envelope["result"]?.object,
              let sdk = result["sdk"]?.object else {
            throw AuditExportResponseError(
                "The Sentry test returned an invalid response. Nothing has been verified."
            )
        }

        let serverError = sdk.text("error")
        guard envelope.flag("success"),
              sdk.flag("initialized"),
              sdk.flag("logsEnabled"),
              sdk.flag("queueDrained"),
              sdk.flag("transportAccepted") else {
            throw AuditExportResponseError(
                serverError.isEmpty
                    ? "Sentry Logs did not accept the verification probe. Check the website's Sentry configuration before exporting."
                    : "Sentry Logs test failed: \(serverError)"
            )
        }

        probeID = result.text("probeId")
        deliveryBatchID = sdk.text("deliveryBatchId")
        guard !probeID.isEmpty, !deliveryBatchID.isEmpty else {
            throw AuditExportResponseError(
                "Sentry accepted the test without returning its verification IDs. Deploy the tracked Sentry exporter before continuing."
            )
        }
    }

    var searchQuery: String {
        "source:patlau_sentry_probe probe_id:\(probeID)"
    }
}

struct AuditExportResponseError: LocalizedError, Equatable {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? { message }
}

private struct AuditOperationAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct AuditLogsView: View {
    @EnvironmentObject private var state: AppState

    @State private var logs: [DynamicRecord] = []
    @State private var metrics: JSONObject = [:]
    @State private var exportHealth: JSONObject?
    @State private var retentionDays = 7
    @State private var pruningEnabled = false
    @State private var total = 0
    @State private var page = 1
    @State private var pageSize = 50
    @State private var search = ""
    @State private var category = ""
    @State private var outcome = ""
    @State private var action = ""
    @State private var usesFromDate = false
    @State private var usesToDate = false
    @State private var fromDate = Date().addingTimeInterval(-7 * 24 * 60 * 60)
    @State private var toDate = Date()
    @State private var showFilters = false
    @State private var filterError: String?
    @State private var selectedLog: DynamicRecord?
    @State private var loading = false
    @State private var exporting = false
    @State private var testingSentry = false
    @State private var sentryLogsURL: URL?
    @State private var sentryProbe: SentryProbeReceipt?
    @State private var probeVisibilityConfirmed = false
    @State private var lastExport: AuditExportReceipt?
    @State private var showExportConfirmation = false
    @State private var showProbeVisibilityConfirmation = false
    @State private var operationAlert: AuditOperationAlert?

    private var totalPages: Int {
        max(1, Int(ceil(Double(total) / Double(max(pageSize, 1)))))
    }

    private var filterCount: Int {
        [category, outcome, action].filter { !$0.isEmpty }.count
            + (usesFromDate ? 1 : 0)
            + (usesToDate ? 1 : 0)
    }

    var body: some View {
        Group {
            if state.role != .superuser {
                ContentUnavailableView(
                    "Superuser Access Required",
                    systemImage: "lock.shield",
                    description: Text("Audit logs contain sensitive operational and security information.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        auditIntroduction
                        auditMetrics
                        exportCard
                        searchAndFilters

                        HStack(alignment: .bottom, spacing: 16) {
                            SectionHeading(
                                title: "Recent activity",
                                subtitle: "\(total) matching \(total == 1 ? "event" : "events") • Page \(page) of \(totalPages)"
                            )
                            DataRefreshButton(scope: "filtered audit activity") {
                                await load()
                            }
                        }

                        if logs.isEmpty && !loading {
                            EmptyState(
                                icon: "list.clipboard",
                                title: "No matching activity",
                                message: "Adjust or reset the filters to see more records."
                            )
                        } else {
                            ForEach(logs) { log in
                                Button { selectedLog = log } label: {
                                    AuditLogRow(log: log)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        pagination
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Theme.background)
            }
        }
        .navigationTitle("Audit Logs")
        .task(id: search) {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            page = 1
            await load()
        }
        .refreshable { await load() }
        .sheet(isPresented: $showFilters) { filterSheet }
        .sheet(item: $selectedLog) { AuditLogDetailSheet(log: $0) }
        .alert("Export queued audit logs?", isPresented: $showExportConfirmation) {
            Button("Export to Sentry") {
                Task { await exportNow() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Only rows accepted by the tracked Sentry transport will move from Pending into the locally retained acknowledgement buffer. The export run ID can then be searched in Sentry Logs.")
        }
        .alert("Can you see the probe in Sentry Logs?", isPresented: $showProbeVisibilityConfirmation) {
            Button("Yes, I Found It") {
                probeVisibilityConfirmed = true
            }
            Button("Not Yet", role: .cancel) {}
        } message: {
            Text(sentryProbe.map { "Search for \($0.searchQuery). Confirm only after that record appears in the intended Sentry project." } ?? "Run the Sentry test first.")
        }
        .alert(item: $operationAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay {
            if loading {
                LoadingOverlay(text: "Loading audit activity")
            }
        }
    }

    private var auditIntroduction: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Recent Supabase activity", systemImage: "lock.doc.fill")
                .font(.headline)
                .foregroundStyle(Theme.purple)
            Text("Understand important security, attendance, payment, support and data-change activity.")
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .lineSpacing(2)
            Text("The current local retention window is \(retentionDays) days.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.purple)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard()
    }

    private var auditMetrics: some View {
        HStack(spacing: 0) {
            auditMetric("Today", value: Int(metrics.number("today")), color: Theme.blue)
            Divider().frame(height: 42)
            auditMetric("Attention", value: Int(metrics.number("attention")), color: Theme.red)
            Divider().frame(height: 42)
            auditMetric("Matching", value: Int(metrics.number("matching")), color: Theme.purple)
        }
        .appCard(padding: 12)
    }

    private func auditMetric(_ title: String, value: Int, color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(value)")
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Audit export health",
                subtitle: pruningEnabled
                    ? "Acknowledged events are cleaned up only after both safety windows."
                    : "Local cleanup remains paused while Sentry visibility is being verified."
            )

            if let exportHealth {
                LazyVGrid(
                    columns: [GridItem(.flexible()), GridItem(.flexible())],
                    spacing: 12
                ) {
                    exportMetric("Pending", value: exportHealth.number("pending"), color: Theme.blue)
                    exportMetric("Retry", value: exportHealth.number("retry"), color: Theme.amber)
                    exportMetric("In flight", value: exportHealth.number("inFlight"), color: Theme.teal)
                    exportMetric("Failed", value: exportHealth.number("dead"), color: Theme.red)
                }

                Divider()
                auditValueRow(
                    "Last successful export",
                    value: exportHealth.text("lastExportedAt").isEmpty
                        ? "Not yet exported"
                        : appDateTime(exportHealth.text("lastExportedAt"))
                )
                auditValueRow(
                    "Oldest waiting event",
                    value: exportHealth.text("oldestPendingAt").isEmpty
                        ? "Nothing waiting"
                        : appDateTime(exportHealth.text("oldestPendingAt"))
                )
                auditValueRow(
                    "Sentry-acknowledged buffer",
                    value: "\(Int(exportHealth.number("exportedBuffered")))"
                )
                auditValueRow(
                    "Automatic cleanup",
                    value: pruningEnabled
                        ? "Enabled after safety windows"
                        : "Paused until verified"
                )

                Divider()

                VStack(alignment: .leading, spacing: 10) {
                    if let sentryProbe {
                        Label(
                            probeVisibilityConfirmed
                                ? "Probe visibility confirmed"
                                : "Transport accepted the probe; confirm it is searchable",
                            systemImage: probeVisibilityConfirmed
                                ? "checkmark.seal.fill"
                                : "exclamationmark.magnifyingglass"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            probeVisibilityConfirmed ? Theme.green : Theme.amber
                        )

                        Text(sentryProbe.searchQuery)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)

                        if !probeVisibilityConfirmed {
                            Button("Confirm Probe Visibility") {
                                showProbeVisibilityConfirmation = true
                            }
                            .buttonStyle(.plain)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.purple)
                        }
                    } else {
                        Label(
                            "Test Sentry first. Export remains locked until its probe is visible in Logs.",
                            systemImage: "shield.lefthalf.filled"
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    if let lastExport {
                        Text("Last export search")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                        Text(lastExport.searchQuery)
                            .font(.caption2.monospaced())
                            .foregroundStyle(Theme.secondaryText)
                            .textSelection(.enabled)
                    }

                    if let sentryLogsURL {
                        Link(destination: sentryLogsURL) {
                            Label("Open Sentry Logs", systemImage: "arrow.up.right.square")
                        }
                        .font(.caption.weight(.semibold))
                    } else {
                        Label(
                            "Add SENTRY_AUDIT_SEARCH_URL in Vercel to open the verified Logs view here.",
                            systemImage: "link.badge.plus"
                        )
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                    }

                    HStack(spacing: 22) {
                        Button {
                            Task { await testSentry() }
                        } label: {
                            if testingSentry {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Test Sentry", systemImage: "checkmark.shield")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.teal)
                        .disabled(testingSentry || exporting)
                        .accessibilityIdentifier("test-sentry")

                        Button {
                            showExportConfirmation = true
                        } label: {
                            if exporting {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Export", systemImage: "arrow.up.doc")
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(
                            probeVisibilityConfirmed ? Theme.purple : Theme.secondaryText
                        )
                        .disabled(exporting || testingSentry || !probeVisibilityConfirmed)
                        .accessibilityIdentifier("export-audit-logs")
                    }
                }
            } else {
                Label(
                    "Export monitoring appears after the audit offload migration is installed.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .appCard()
    }

    private func exportMetric(_ title: String, value: Double, color: Color) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(Theme.secondaryText)
                Text("\(Int(value))")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(color)
            }
            Spacer()
        }
        .padding(12)
        .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    private func auditValueRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.trailing)
        }
    }

    private var searchAndFilters: some View {
        VStack(spacing: 12) {
            AppSearchField(
                prompt: "Person, student, payment or summary",
                text: $search
            )
            Button { showFilters = true } label: {
                HStack {
                    Label("Filters", systemImage: "line.3.horizontal.decrease")
                    Spacer()
                    if filterCount > 0 {
                        Text("\(filterCount)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                            .background(Theme.purple, in: Circle())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(Theme.ink)
            }
            .buttonStyle(.plain)
            .appCard(padding: 14)
        }
    }

    private var pagination: some View {
        HStack {
            Button("Previous") {
                page = max(1, page - 1)
                Task { await load() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(page > 1 ? Theme.purple : Theme.secondaryText)
            .disabled(page <= 1 || loading)

            Spacer()
            Text("Page \(page) of \(totalPages)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Spacer()

            Button("Next") {
                page = min(totalPages, page + 1)
                Task { await load() }
            }
            .buttonStyle(.plain)
            .foregroundStyle(page < totalPages ? Theme.purple : Theme.secondaryText)
            .disabled(page >= totalPages || loading)
        }
        .padding(.vertical, 8)
    }

    private var filterSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Audit Filters",
                    onCancel: { showFilters = false },
                    actionTitle: "Apply",
                    onAction: applyFilters
                )
                Form {
                    Section("Activity") {
                        Picker("Category", selection: $category) {
                            Text("All categories").tag("")
                            ForEach(auditCategories, id: \.self) {
                                Text(auditCategoryLabel($0)).tag($0)
                            }
                        }
                        Picker("Outcome", selection: $outcome) {
                            Text("All outcomes").tag("")
                            ForEach(auditOutcomes, id: \.self) {
                                Text(auditOutcomeLabel($0)).tag($0)
                            }
                        }
                        TextField("Action, e.g. update or reset", text: $action)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }

                    Section("Date range") {
                        Toggle("Use start date", isOn: $usesFromDate)
                        if usesFromDate {
                            DatePicker("From", selection: $fromDate, displayedComponents: .date)
                        }
                        Toggle("Use end date", isOn: $usesToDate)
                        if usesToDate {
                            DatePicker("To", selection: $toDate, displayedComponents: .date)
                        }
                        if let filterError {
                            Text(filterError)
                                .font(.caption)
                                .foregroundStyle(Theme.red)
                        }
                    }

                    Section {
                        Button("Reset Filters", role: .destructive) { resetFilters() }
                            .buttonStyle(.plain)
                    }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
    }

    private func applyFilters() {
        if usesFromDate && usesToDate && fromDate > toDate {
            filterError = "The start date must be before the end date."
            return
        }
        filterError = nil
        showFilters = false
        page = 1
        Task { await load() }
    }

    private func resetFilters() {
        category = ""
        outcome = ""
        action = ""
        usesFromDate = false
        usesToDate = false
        filterError = nil
        page = 1
        showFilters = false
        Task { await load() }
    }

    private func load() async {
        guard state.role == .superuser else { return }
        loading = logs.isEmpty
        defer { loading = false }
        do {
            let response = try await BackendClient.shared.websiteJSON(path: auditRequestPath)
            let object = response.object ?? [:]
            logs = object["logs"]?.array?
                .compactMap(\.object)
                .map(DynamicRecord.init) ?? []
            total = Int(object.number("total"))
            page = Int(object.number("page", fallback: Double(page)))
            pageSize = Int(object.number("pageSize", fallback: 50))
            metrics = object["metrics"]?.object ?? [:]
            retentionDays = Int(object.number("retentionDays", fallback: 7))
            pruningEnabled = object.flag("pruningEnabled")
            exportHealth = object["exportHealth"]?.object
            sentryLogsURL = object["sentryLogsUrl"]?.string.flatMap { value in
                guard let url = URL(string: value), url.scheme == "https" else {
                    return nil
                }
                return url
            }
        } catch {
            state.show(error)
        }
    }

    private var auditRequestPath: String {
        var components = URLComponents()
        components.path = "/api/audit/events"
        var items = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "pageSize", value: "50")
        ]
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAction = action.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty { items.append(.init(name: "search", value: trimmedSearch)) }
        if !category.isEmpty { items.append(.init(name: "category", value: category)) }
        if !outcome.isEmpty { items.append(.init(name: "outcome", value: outcome)) }
        if !trimmedAction.isEmpty { items.append(.init(name: "action", value: trimmedAction)) }
        if usesFromDate { items.append(.init(name: "from", value: fromDate.isoDateKey)) }
        if usesToDate { items.append(.init(name: "to", value: toDate.isoDateKey)) }
        components.queryItems = items
        return components.string ?? "/api/audit/events?page=\(page)&pageSize=50"
    }

    private func exportNow() async {
        guard !exporting else { return }
        guard probeVisibilityConfirmed else {
            operationAlert = AuditOperationAlert(
                title: "Verify Sentry First",
                message: "Run Test Sentry, find the probe in Sentry Logs, and confirm its visibility before exporting queued audit records."
            )
            return
        }
        exporting = true
        let activity = state.beginActivity("Exporting audit logs to Sentry…")
        defer {
            exporting = false
            state.endActivity(activity)
        }
        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "/api/audit/export",
                method: "POST"
            )
            let receipt = try AuditExportReceipt(response: response)
            lastExport = receipt

            let message: String
            if receipt.exported > 0 {
                message = "Sentry's tracked transport accepted \(receipt.exported) audit event\(receipt.exported == 1 ? "" : "s"). Local copies remain retained. Verify them with \(receipt.searchQuery)."
            } else {
                message = "No queued audit events needed export. Run ID: \(receipt.exportRunID)."
            }
            operationAlert = AuditOperationAlert(
                title: "Export Transport Completed",
                message: message + (receipt.requeued > 0 ? " \(receipt.requeued) failed event\(receipt.requeued == 1 ? " was" : "s were") requeued first." : "")
            )
            await load()
        } catch {
            operationAlert = AuditOperationAlert(
                title: "Audit Export Failed",
                message: error.localizedDescription
            )
        }
    }

    private func testSentry() async {
        guard !testingSentry else { return }
        testingSentry = true
        probeVisibilityConfirmed = false
        sentryProbe = nil
        let activity = state.beginActivity("Testing Sentry Logs delivery…")
        defer {
            testingSentry = false
            state.endActivity(activity)
        }

        do {
            let response = try await BackendClient.shared.websiteJSON(
                path: "/api/audit/sentry-probe",
                method: "POST"
            )
            let receipt = try SentryProbeReceipt(response: response)
            sentryProbe = receipt
            operationAlert = AuditOperationAlert(
                title: "Sentry Transport Accepted the Probe",
                message: "This confirms SDK delivery, not search visibility. Find \(receipt.searchQuery) in the intended Sentry project, then tap Confirm Probe Visibility."
            )
            await load()
        } catch {
            operationAlert = AuditOperationAlert(
                title: "Sentry Test Failed",
                message: error.localizedDescription
            )
        }
    }
}

private struct AuditLogRow: View {
    let log: DynamicRecord

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            Text(String(auditCategoryLabel(log.values.text("category")).prefix(1)))
                .font(.headline.bold())
                .foregroundStyle(auditCategoryColor(log.values.text("category")))
                .frame(width: 40, height: 40)
                .background(
                    auditCategoryColor(log.values.text("category")).opacity(0.1),
                    in: RoundedRectangle(cornerRadius: 11)
                )

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(auditCategoryLabel(log.values.text("category")))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(auditCategoryColor(log.values.text("category")))
                    Spacer(minLength: 8)
                    Text(appDateTime(log.values.text("occurred_at")))
                        .font(.caption2)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(log.values.text("summary", fallback: "Recorded activity"))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.leading)
                HStack(spacing: 6) {
                    Text(auditActor(log))
                    let target = log.values.text("target_label")
                    if !target.isEmpty {
                        Text("•")
                        Text(target)
                    }
                }
                .font(.caption)
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(2)
                StatusBadge(
                    text: auditOutcomeLabel(log.values.text("outcome")),
                    color: auditOutcomeColor(log.values.text("outcome"))
                )
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .padding(.top, 12)
        }
        .appCard()
    }
}

private struct AuditLogDetailSheet: View {
    @Environment(\.dismiss) private var dismiss

    let log: DynamicRecord
    @State private var copied = false

    private var changedFields: [String] {
        let explicit = log.values["changed_fields"]?.array?.compactMap(\.string) ?? []
        if !explicit.isEmpty { return explicit }
        let oldKeys = Set(log.values["old_values"]?.object?.keys ?? Dictionary<String, JSONValue>().keys)
        let newKeys = Set(log.values["new_values"]?.object?.keys ?? Dictionary<String, JSONValue>().keys)
        return Array(oldKeys.union(newKeys)).sorted()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                PlainSheetHeader(
                    title: "Activity Details",
                    cancelTitle: "Done",
                    onCancel: { dismiss() }
                )

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Event #\(log.values.text("id"))")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(Theme.purple)
                                Spacer()
                                StatusBadge(
                                    text: auditOutcomeLabel(log.values.text("outcome")),
                                    color: auditOutcomeColor(log.values.text("outcome"))
                                )
                            }
                            Text(log.values.text("summary", fallback: "Recorded activity"))
                                .font(.title3.bold())
                                .foregroundStyle(Theme.ink)
                            LabeledContent("Recorded", value: appDateTime(log.values.text("occurred_at")))
                                .font(.caption)
                        }
                        .appCard()

                        detailSection("Who and what") {
                            detailRow("Actor", auditActor(log))
                            detailRow("Role", auditHumanise(log.values.text("actor_role")))
                            detailRow("Source", auditHumanise(log.values.text("actor_source")))
                            detailRow("Category", auditCategoryLabel(log.values.text("category")))
                            detailRow("Action", auditHumanise(log.values.text("action")))
                            detailRow(
                                "Target",
                                log.values.text(
                                    "target_label",
                                    fallback: auditHumanise(log.values.text("target_table"))
                                )
                            )
                        }

                        if !changedFields.isEmpty {
                            SectionHeading(
                                title: "Recorded changes",
                                subtitle: "Values captured before and after the action."
                            )
                            ForEach(changedFields, id: \.self) { field in
                                VStack(alignment: .leading, spacing: 10) {
                                    Text(auditHumanise(field))
                                        .font(.subheadline.weight(.bold))
                                        .foregroundStyle(Theme.ink)
                                    changeValue(
                                        "Before",
                                        value: log.values["old_values"]?.object?[field]
                                    )
                                    HStack {
                                        Spacer()
                                        Image(systemName: "arrow.down")
                                            .foregroundStyle(Theme.secondaryText)
                                        Spacer()
                                    }
                                    changeValue(
                                        "After",
                                        value: log.values["new_values"]?.object?[field]
                                    )
                                }
                                .appCard()
                            }
                        }

                        detailSection("Request information") {
                            detailRow("Page or endpoint", log.values.text("request_path", fallback: "—"), mono: true)
                            detailRow("Method", log.values.text("request_method", fallback: "—"), mono: true)
                            detailRow("IP address", log.values.text("ip_address", fallback: "—"), mono: true)
                            detailRow("Event type", log.values.text("event_type", fallback: "—"), mono: true)

                            let requestID = log.values.text("request_id")
                            if !requestID.isEmpty {
                                Divider()
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Request ID")
                                            .font(.caption)
                                            .foregroundStyle(Theme.secondaryText)
                                        Text(requestID)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    }
                                    Spacer(minLength: 10)
                                    Button(copied ? "Copied" : "Copy") {
                                        UIPasteboard.general.string = requestID
                                        copied = true
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.purple)
                                }
                            }
                        }

                        DisclosureGroup("Technical details") {
                            VStack(alignment: .leading, spacing: 12) {
                                detailRow("Target table", log.values.text("target_table", fallback: "—"), mono: true)
                                detailRow("Target record", auditDisplayValue(log.values["target_record_id"]), mono: true)
                                detailRow("Metadata", auditDisplayValue(log.values["metadata"]), mono: true)
                                detailRow("User agent", log.values.text("user_agent", fallback: "—"), mono: true)
                            }
                            .padding(.top, 12)
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .appCard()
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 20)
                }
                .background(Theme.background)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.large])
    }

    private func detailSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
            content()
        }
        .appCard()
    }

    private func detailRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(mono ? .caption.monospaced() : .subheadline)
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func changeValue(_ label: String, value: JSONValue?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Theme.secondaryText)
            Text(auditDisplayValue(value))
                .font(.caption.monospaced())
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: 9))
        }
    }
}
