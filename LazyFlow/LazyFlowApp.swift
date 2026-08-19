import SwiftUI

@main
struct LazyFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let updaterService = UpdaterService.shared

    var body: some Scene {
        Window("LazyFlow", id: "main") {
            MainWindowView()
                .environment(appDelegate.appState)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }

            CommandGroup(after: .appInfo) {
                CheckForUpdatesButton(updaterService: updaterService)
            }

            // LazyFlow is useful even without an open window: the menu-bar item
            // and global dictation hotkey continue to work in the background.
            CommandGroup(replacing: .appTermination) {
                Button("Run LazyFlow in Background") {
                    appDelegate.runInBackground()
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }

        MenuBarExtra {
            MenuBarView()
                .environment(appDelegate.appState)
        } label: {
            MenuBarIcon(appState: appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.appState)
        }
    }
}
