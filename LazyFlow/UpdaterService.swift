import Foundation
import Sparkle

// Thin wrapper around Sparkle's standard updater.
//
// Configuration lives in Info.plist:
//   • SUFeedURL          — the appcast.xml URL for your releases
//   • SUPublicEDKey      — the EdDSA public key that signs your updates
//   • SUEnableAutomaticChecks — YES to check in the background
//
// Generate the key pair with Sparkle's `generate_keys` tool, sign each release with
// `sign_update`, and publish an appcast (see `generate_appcast`). Until SUFeedURL is
// set, `canCheckForUpdates` is false and the menu item stays disabled.
@MainActor
final class UpdaterService {
    static let shared = UpdaterService()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
