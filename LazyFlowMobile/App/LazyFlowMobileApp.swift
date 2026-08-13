import SwiftUI
import UIKit
import UserNotifications

extension Notification.Name {
    static let lazyFlowQuickStart = Notification.Name("lazyFlowQuickStart")
}

final class LazyFlowAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == QuickOpenNotification.requestIdentifier else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .lazyFlowQuickStart, object: nil)
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
