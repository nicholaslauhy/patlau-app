import SwiftUI

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
        }
    }
}
