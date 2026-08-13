import SwiftUI

@main
struct LazyFlowMobileApp: App {
    @StateObject private var session = DictationSessionController()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .task { session.startMonitoring() }
        }
    }
}
