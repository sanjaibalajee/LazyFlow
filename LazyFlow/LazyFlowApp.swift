import SwiftUI

@main
struct LazyFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("LazyFlow", id: "main") {
            MainWindowView()
                .environment(appDelegate.appState)
        }
        .defaultSize(width: 960, height: 620)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
