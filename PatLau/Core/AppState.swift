import Foundation
import Combine

struct SupportConversationDeepLink: Equatable, Sendable {
    static let path = "/open-in-app/chats"
    static let customScheme = "patlau"
    static let customHost = "chats"

    let conversationID: String

    static func parse(
        _ url: URL,
        websiteURL: URL = AppConfiguration.websiteURL
    ) -> SupportConversationDeepLink? {
        let isTrustedWebsiteLink = url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == websiteURL.host?.lowercased()
            && url.port == websiteURL.port
            && url.path == path
        let isPatLauAppLink = url.scheme?.lowercased() == customScheme
            && url.host?.lowercased() == customHost
            && url.port == nil
            && (url.path.isEmpty || url.path == "/")

        guard (isTrustedWebsiteLink || isPatLauAppLink),
              url.user == nil,
              url.password == nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.fragment == nil,
              let queryItems = components.queryItems,
              queryItems.count == 1,
              queryItems[0].name == "conversation",
              let value = queryItems[0].value?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              value.range(
                of: #"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89aAbB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }

        return SupportConversationDeepLink(conversationID: value.lowercased())
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var role: UserRole = .member
    @Published private(set) var isResolvingRole = false
    @Published private(set) var hasResolvedAccount = false
    @Published var notice: AppNotice?
    @Published private(set) var activity: AppActivity?
    @Published private(set) var avatarRevision = UUID()
    @Published private(set) var pendingConversationID: String?

    private var activities: [UUID: AppActivity] = [:]
    private var activityOrder: [UUID] = []
    private var accountResolutionID: UUID?
    private var lastAcceptedConversationID: String?
    private var lastAcceptedConversationAt: Date?

    var user: AuthUser? { session?.user }

    init() {
#if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            let roleArgument = ProcessInfo.processInfo.arguments.first {
                $0.hasPrefix("-uiTestingRole=")
            }
            let requestedRole = roleArgument?
                .replacingOccurrences(of: "-uiTestingRole=", with: "")
            let testRole = requestedRole.flatMap(UserRole.init(rawValue:)) ?? .superuser
            let testUser = AuthUser(
                id: "ui-test-user",
                email: "ui-test@patlau.local",
                userMetadata: [
                    "name": .string("UI Test User")
                ],
                appMetadata: [
                    "role": .string(testRole.rawValue)
                ]
            )
            session = AuthSession(
                accessToken: "ui-test-access-token",
                refreshToken: "ui-test-refresh-token",
                expiresIn: 3_600,
                expiresAt: Date().addingTimeInterval(3_600).timeIntervalSince1970,
                tokenType: "bearer",
                user: testUser
            )
            role = testRole
            hasResolvedAccount = true
            if let conversationArgument = ProcessInfo.processInfo.arguments.first(where: {
                $0.hasPrefix("-uiTestingConversation=")
            }) {
                let conversationID = conversationArgument.replacingOccurrences(
                    of: "-uiTestingConversation=",
                    with: ""
                )
                if let url = URL(
                    string: "\(SupportConversationDeepLink.customScheme)://\(SupportConversationDeepLink.customHost)?conversation=\(conversationID)"
                ) {
                    _ = handleIncomingURL(url)
                }
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTestingNotice") {
                notice = AppNotice(
                    text: "Profile photo updated.",
                    kind: .success
                )
            }
            if ProcessInfo.processInfo.arguments.contains("-uiTestingActivity") {
                _ = beginActivity("Updating attendance status…")
            }
            return
        }
#endif
        // PatLau requires a fresh sign-in on every cold launch. Remove any
        // session left by older app builds so rebuilding in Xcode cannot skip
        // the login screen through a Keychain restore.
        KeychainStore.delete(account: "session")
    }

    func signIn(identifier: String, password: String) async throws {
        guard AppConfiguration.isConfigured else {
            throw BackendError.message(
                "Configure the Supabase project URL and publishable key first."
            )
        }

        let signedIn = try await BackendClient.shared.signIn(
            identifier: identifier,
            password: password
        )
        await accept(signedIn, resolveAccount: true)
    }

    func completePasswordReset(
        password: String,
        recoverySession: AuthSession
    ) async throws {
        let signedIn = try await BackendClient.shared.completePasswordReset(
            password: password,
            recoverySession: recoverySession
        )
        await accept(signedIn, resolveAccount: true)
    }

    func refreshAccount() async {
        guard let startingSession = session, !isResolvingRole else { return }
        let expectedUserID = startingSession.user.id
        let resolutionID = UUID()
        accountResolutionID = resolutionID
        var trustedRoleResolved = Self.trustedRole(for: startingSession.user) != nil
        isResolvingRole = true
        hasResolvedAccount = false
        defer {
            if accountResolutionID == resolutionID,
               session?.user.id == expectedUserID {
                isResolvingRole = false
                hasResolvedAccount = trustedRoleResolved
                if !trustedRoleResolved, pendingConversationID != nil {
                    show(
                        "Your account access could not be verified. The conversation link is still waiting; refresh your account or sign in again.",
                        kind: .error
                    )
                }
            }
        }

        if let expiry = session?.expiryDate,
           expiry < Date().addingTimeInterval(5 * 60),
           let refreshed = try? await BackendClient.shared.refreshSession() {
            guard session?.user.id == expectedUserID else { return }
            session = refreshed
            role = refreshed.user.role
            trustedRoleResolved = Self.trustedRole(for: refreshed.user) != nil
        }

        if let latestUser = try? await BackendClient.shared.fetchCurrentUser() {
            guard session?.user.id == expectedUserID else { return }
            // fetchCurrentUser may refresh an expired access token internally.
            // Keep the actor's latest tokens while replacing stale user metadata.
            let latestSession = await BackendClient.shared.currentSession() ?? session
            if let latestSession {
                let updated = latestSession.replacingUser(latestUser)
                session = updated
                role = latestUser.role
                trustedRoleResolved = Self.trustedRole(for: latestUser) != nil
                await BackendClient.shared.setSession(updated)
            }
        }

        // This RPC is the protected role used by current website APIs and RLS.
        // If that migration is not deployed yet, valid user metadata remains the fallback.
        let protectedRole = try? await BackendClient.shared.currentRole()
        guard session?.user.id == expectedUserID else { return }

        // currentRole can refresh the access token. Merge the newest tokens and role
        // into one in-memory session so the current app run uses the protected role.
        if var finalSession = await BackendClient.shared.currentSession() ?? session {
            if let protectedRole {
                finalSession = finalSession.replacingUser(
                    finalSession.user.replacingRole(protectedRole)
                )
                role = protectedRole
                trustedRoleResolved = true
            } else if let trustedRole = Self.trustedRole(for: finalSession.user) {
                role = trustedRole
                trustedRoleResolved = true
            } else {
                role = finalSession.user.role
            }

            session = finalSession
            await BackendClient.shared.setSession(finalSession)
        }
    }

    func signOut() {
        let signedOutAccessToken = session?.accessToken
        session = nil
        role = .member
        isResolvingRole = false
        hasResolvedAccount = false
        accountResolutionID = nil
        notice = nil
        activities.removeAll()
        activityOrder.removeAll()
        activity = nil
        reloadAvatar()
        KeychainStore.delete(account: "session")
        Task {
            // Do not let a delayed cleanup task erase a newer session if the
            // user signs back in before this actor hop runs.
            await BackendClient.shared.clearSession(
                ifAccessTokenMatches: signedOutAccessToken
            )
        }
    }

    @discardableResult
    func handleIncomingURL(_ url: URL) -> Bool {
        guard let link = SupportConversationDeepLink.parse(url) else { return false }
        let now = Date()
        if lastAcceptedConversationID == link.conversationID,
           let previous = lastAcceptedConversationAt,
           now.timeIntervalSince(previous) < 2 {
            return true
        }
        lastAcceptedConversationID = link.conversationID
        lastAcceptedConversationAt = now
        pendingConversationID = link.conversationID
        return true
    }

    func takePendingConversationID() -> String? {
        defer { pendingConversationID = nil }
        return pendingConversationID
    }

    func show(_ text: String, kind: AppNotice.Kind = .success) {
        notice = AppNotice(text: text, kind: kind)
    }

    /// Presents genuine failures while treating view/task cancellation as the
    /// expected lifecycle event it is. SwiftUI cancels a view's `.task` when
    /// navigating away, and URLSession reports that as URLError.cancelled.
    func show(_ error: Error) {
        guard !error.isExpectedCancellation else { return }
        show(error.localizedDescription, kind: .error)
    }

    @discardableResult
    func beginActivity(_ message: String) -> UUID {
        let value = AppActivity(message: message)
        activities[value.id] = value
        activityOrder.append(value.id)
        activity = value
        return value.id
    }

    func endActivity(_ id: UUID) {
        activities[id] = nil
        activityOrder.removeAll { $0 == id }
        activity = activityOrder.last.flatMap { activities[$0] }
    }

    func reloadAvatar() {
        avatarRevision = UUID()
    }

    private func accept(_ value: AuthSession, resolveAccount: Bool) async {
        accountResolutionID = nil
        session = value
        role = value.user.role
        hasResolvedAccount = false
        await BackendClient.shared.setSession(value)

        if resolveAccount {
            await refreshAccount()
        } else {
            hasResolvedAccount = true
        }
    }

    private static func trustedRole(for user: AuthUser) -> UserRole? {
        guard let value = user.appMetadata?["role"]?.string else { return nil }
        return UserRole(rawValue: value)
    }
}

struct AppNotice: Identifiable, Equatable {
    enum Kind: Equatable {
        case success
        case error
        case info
    }

    let id = UUID()
    let text: String
    let kind: Kind
}

struct AppActivity: Identifiable, Equatable {
    let id = UUID()
    let message: String
}

extension Error {
    var isExpectedCancellation: Bool {
        if self is CancellationError {
            return true
        }

        let error = self as NSError
        if error.domain == NSURLErrorDomain,
           error.code == URLError.cancelled.rawValue {
            return true
        }

        // Some URL loading layers wrap the original cancellation. Inspect one
        // underlying error without relying on its localized text.
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? Error {
            let nested = underlying as NSError
            guard nested.domain != error.domain || nested.code != error.code else {
                return false
            }
            return underlying.isExpectedCancellation
        }

        return false
    }
}
