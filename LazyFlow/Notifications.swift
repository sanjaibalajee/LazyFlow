import Foundation

// App-internal notifications used to bridge SwiftUI menu items to the AppDelegate,
// which owns the onboarding controller and the updater.
extension Notification.Name {
    static let lazyflowOpenSetup       = Notification.Name("lazyflowOpenSetup")
    static let lazyflowCheckForUpdates = Notification.Name("lazyflowCheckForUpdates")
}
