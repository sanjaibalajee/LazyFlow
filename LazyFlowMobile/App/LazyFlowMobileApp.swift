import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let lazyFlowStartSessionRequested = Notification.Name("lazyFlowStartSessionRequested")
}

final class LazyFlowAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        KeyboardHandoffDiagnostics.record(
            .app,
            "Application launched",
            details: launchOptions == nil ? "standard launch" : "launch options present"
        )
        return true
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        KeyboardHandoffDiagnostics.record(.app, "Application became active")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        KeyboardHandoffDiagnostics.record(
            .notification,
            "Notification response received by app",
            details: "identifier=\(identifier)"
        )
        guard identifier == KeyboardHandoffNotification.requestIdentifier else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .lazyFlowStartSessionRequested, object: nil)
        }
    }
}

@main
struct LazyFlowMobileApp: App {
    @UIApplicationDelegateAdaptor(LazyFlowAppDelegate.self) private var appDelegate
    @StateObject private var session = DictationSessionController()

    var body: some Scene {
        WindowGroup {
            RootView(session: session)
                .task { session.startMonitoring() }
        }
    }
}
