import SwiftUI
import WebKit
import UIKit

struct WebPortalPage: View {
    @EnvironmentObject private var state: AppState

    let title: String
    let url: URL

    @StateObject private var model = WebPortalModel()

    init(operation: PortalOperation) {
        title = operation.title
        url = operation.webURL
    }

    init(title: String, path: String) {
        self.title = title
        url = URL(string: path, relativeTo: AppConfiguration.websiteURL)?.absoluteURL
            ?? AppConfiguration.websiteURL
    }

    var body: some View {
        ZStack(alignment: .top) {
            PortalWebView(
                url: url,
                session: state.session,
                model: model
            )

            if model.isLoading {
                ProgressView()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }

            if let errorMessage = model.errorMessage {
                ContentUnavailableView {
                    Label("Unable to Open Website", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") { model.reload() }
                }
                .padding()
                .background(Theme.background)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task(id: state.user?.id) {
            await maintainAuthenticatedSession()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Reload")
            }
        }
    }

    private func maintainAuthenticatedSession() async {
        await state.refreshAccount()

        // Supabase's browser client rotates access and refresh tokens. Refresh
        // natively first and pass the new session back into WKWebView so a long
        // portal visit cannot leave the native and browser sessions out of sync.
        while !Task.isCancelled {
            guard let session = state.session,
                  let expiry = session.expiryDate else {
                return
            }

            let accessToken = session.accessToken
            let refreshDate = expiry.addingTimeInterval(-10 * 60)
            let delay = max(refreshDate.timeIntervalSinceNow, 1)

            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }

            await state.refreshAccount()

            // A transient network failure leaves the old token in place. Avoid
            // a tight retry loop once its planned refresh time has passed.
            if state.session?.accessToken == accessToken {
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    return
                }
            }
        }
    }
}

@MainActor
private final class WebPortalModel: ObservableObject {
    @Published var isLoading = false
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    func update(from webView: WKWebView) {
        self.webView = webView
        if isLoading != webView.isLoading {
            isLoading = webView.isLoading
        }
    }

    func reload() {
        errorMessage = nil
        webView?.reload()
    }
}

private struct PortalWebView: UIViewRepresentable {
    let url: URL
    let session: AuthSession?
    @ObservedObject var model: WebPortalModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        // Keep a localStorage copy for pages that use the standard Supabase JS client.
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.localStorageScript(for: session),
                injectionTime: .atDocumentStart,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive

        context.coordinator.sessionFingerprint = session?.accessToken
        model.webView = webView

        Self.synchroniseWebsiteSession(
            session,
            for: url,
            dataStore: configuration.websiteDataStore
        ) {
            webView.load(Self.request(for: url))
        }

        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let fingerprint = session?.accessToken
        guard context.coordinator.sessionFingerprint != fingerprint else {
            return
        }

        context.coordinator.sessionFingerprint = fingerprint
        Self.synchroniseWebsiteSession(
            session,
            for: url,
            dataStore: webView.configuration.websiteDataStore
        ) {
            webView.evaluateJavaScript(Self.localStorageScript(for: session)) { _, _ in
                webView.reload()
            }
        }
    }

    private static func request(for url: URL) -> URLRequest {
        URLRequest(
            url: url,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 45
        )
    }

    private static func synchroniseWebsiteSession(
        _ session: AuthSession?,
        for url: URL,
        dataStore: WKWebsiteDataStore,
        completion: @escaping () -> Void
    ) {
        guard let host = url.host else {
            DispatchQueue.main.async(execute: completion)
            return
        }

        let cookieStore = dataStore.httpCookieStore
        cookieStore.getAllCookies { existingCookies in
            let staleCookies = existingCookies.filter {
                $0.name == storageKey || $0.name.hasPrefix("\(storageKey).")
            }

            let deletionGroup = DispatchGroup()
            for cookie in staleCookies {
                deletionGroup.enter()
                cookieStore.delete(cookie) {
                    deletionGroup.leave()
                }
            }

            deletionGroup.notify(queue: .main) {
                guard let session else {
                    completion()
                    return
                }

                let cookies = authenticationCookies(for: session, host: host)
                guard !cookies.isEmpty else {
                    completion()
                    return
                }

                let insertionGroup = DispatchGroup()
                for cookie in cookies {
                    insertionGroup.enter()
                    cookieStore.setCookie(cookie) {
                        insertionGroup.leave()
                    }
                }

                insertionGroup.notify(queue: .main, execute: completion)
            }
        }
    }

    private static func authenticationCookies(
        for session: AuthSession,
        host: String
    ) -> [HTTPCookie] {
        guard let data = try? JSONEncoder().encode(session) else { return [] }

        let encoded = "base64-" + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        let chunks = chunk(encoded, maximumLength: 3_180)
        let expires = Date().addingTimeInterval(400 * 24 * 60 * 60)

        return chunks.enumerated().compactMap { index, value in
            let name = chunks.count == 1 ? storageKey : "\(storageKey).\(index)"
            return HTTPCookie(properties: [
                .domain: host,
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE",
                .expires: expires
            ])
        }
    }

    private static func chunk(_ value: String, maximumLength: Int) -> [String] {
        guard value.count > maximumLength else { return [value] }

        var chunks: [String] = []
        var start = value.startIndex

        while start < value.endIndex {
            let end = value.index(
                start,
                offsetBy: maximumLength,
                limitedBy: value.endIndex
            ) ?? value.endIndex
            chunks.append(String(value[start..<end]))
            start = end
        }

        return chunks
    }

    private static func localStorageScript(for session: AuthSession?) -> String {
        guard let session,
              let encodedSession = try? JSONEncoder().encode(session),
              let sessionString = String(data: encodedSession, encoding: .utf8),
              let keyLiteral = javaScriptLiteral(storageKey),
              let valueLiteral = javaScriptLiteral(sessionString) else {
            let key = javaScriptLiteral(storageKey) ?? "'sb-patlau-auth-token'"
            return "window.localStorage.removeItem(\(key));"
        }

        return """
        (() => {
            try {
                window.localStorage.setItem(\(keyLiteral), \(valueLiteral));
            } catch (_) {
                // Cookie-based website authentication remains available.
            }
        })();
        """
    }

    private static var storageKey: String {
        let projectReference = AppConfiguration.supabaseURL.host?
            .split(separator: ".")
            .first
            .map(String.init) ?? "patlau"
        return "sb-\(projectReference)-auth-token"
    }

    private static func javaScriptLiteral(_ value: String) -> String? {
        guard let data = try? JSONEncoder().encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let model: WebPortalModel
        private var updatePending = false
        private var shouldClearError = false
        var sessionFingerprint: String?

        init(model: WebPortalModel) {
            self.model = model
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url,
                  let scheme = url.scheme?.lowercased() else {
                decisionHandler(.allow)
                return
            }

            if scheme == "http" || scheme == "https" {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(
            _ webView: WKWebView,
            didStartProvisionalNavigation navigation: WKNavigation!
        ) {
            scheduleModelUpdate(from: webView, clearError: true)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            scheduleModelUpdate(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            scheduleModelUpdate(from: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error, in: webView)
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            show(error, in: webView)
        }

        private func show(_ error: Error, in webView: WKWebView) {
            if (error as NSError).code == NSURLErrorCancelled { return }

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self, let webView else { return }
                self.model.errorMessage = error.localizedDescription
                self.model.update(from: webView)
            }
        }

        /// Defer observable changes until SwiftUI has completed the current
        /// `UIViewRepresentable` update pass. Publishing synchronously from
        /// `updateUIView` causes an invalid render loop and can block WebKit taps.
        private func scheduleModelUpdate(
            from webView: WKWebView,
            clearError: Bool = false
        ) {
            shouldClearError = shouldClearError || clearError
            guard !updatePending else { return }
            updatePending = true

            DispatchQueue.main.async { [weak self, weak webView] in
                guard let self else { return }
                self.updatePending = false
                guard let webView else { return }

                if self.shouldClearError {
                    self.shouldClearError = false
                    self.model.errorMessage = nil
                }
                self.model.update(from: webView)
            }
        }
    }
}
