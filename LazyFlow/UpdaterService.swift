import Combine
import Sparkle
import SwiftUI

/// Owns Sparkle's updater for the lifetime of the app and exposes its state to
/// both the application menu and the menu-bar popover.
@MainActor
final class UpdaterService: ObservableObject {
    static let shared = UpdaterService()

    @Published private(set) var canCheckForUpdates = false

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject var updaterService: UpdaterService

    var body: some View {
        Button("Check for Updates…") {
            updaterService.checkForUpdates()
        }
        .disabled(!updaterService.canCheckForUpdates)
    }
}
