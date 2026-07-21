import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var session: AuthSession?
    @Published private(set) var role: UserRole = .member
    @Published private(set) var isResolvingRole = false
    @Published var notice: AppNotice?
    @Published private(set) var activity: AppActivity?
    @Published private(set) var avatarRevision = UUID()

    private var activities: [UUID: AppActivity] = [:]
    private var activityOrder: [UUID] = []

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
        isResolvingRole = true
        defer { isResolvingRole = false }

        if let expiry = session?.expiryDate,
           expiry < Date().addingTimeInterval(5 * 60),
           let refreshed = try? await BackendClient.shared.refreshSession() {
            guard session?.user.id == expectedUserID else { return }
            session = refreshed
            role = refreshed.user.role
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
        session = value
        role = value.user.role
        await BackendClient.shared.setSession(value)

        if resolveAccount {
            await refreshAccount()
        }
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
