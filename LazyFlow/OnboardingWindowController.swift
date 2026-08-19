import AppKit
import SwiftUI

// Hosts the first-run onboarding as a standalone, centered window.
@MainActor
final class OnboardingWindowController: NSWindowController {
    static let onboardedKey = "lf_onboarded"

    private let appState: AppState
    private let permissions: PermissionsService
    private let onFinish: () -> Void

    init(appState: AppState, permissions: PermissionsService, onFinish: @escaping () -> Void) {
        self.appState = appState
        self.permissions = permissions
        self.onFinish = onFinish

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 660),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.minSize = NSSize(width: 820, height: 660)
        window.maxSize = NSSize(width: 820, height: 660)
        window.center()
        super.init(window: window)

        let root = OnboardingView(appState: appState, permissions: permissions) { [weak self] in
            self?.complete()
        }
        window.contentView = NSHostingView(rootView: root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        NSApp.setActivationPolicy(.regular)   // ensure the window can take focus during setup
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    private func complete() {
        UserDefaults.standard.set(true, forKey: Self.onboardedKey)
        close()
        onFinish()
    }

    static var hasOnboarded: Bool {
        UserDefaults.standard.bool(forKey: onboardedKey)
    }
}
