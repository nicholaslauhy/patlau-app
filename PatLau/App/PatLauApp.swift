import SwiftUI
import Foundation

@main
struct PatLauApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            Group {
                if state.session == nil { LoginView() }
                else { RootView() }
            }
            .environmentObject(state)
            .tint(Theme.blue)
            .preferredColorScheme(.light)
            .onOpenURL { url in
                _ = state.handleIncomingURL(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                _ = state.handleIncomingURL(url)
            }
        }
    }
}
