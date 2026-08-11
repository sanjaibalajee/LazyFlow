import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState              = AppState()
    let permissions           = PermissionsService()
    private let hotkeyManager = HotkeyManager()
    private lazy var overlay  = RecordingOverlayController(appState: appState)
    private var onboardingController: OnboardingWindowController?
    private var hotkeysRunning = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Apply the Dock-icon preference before any window appears.
        AppState.applyActivationPolicy(showDockIcon: appState.showDockIcon)
        configureHotkeyCallbacks()
        observeRecordingState()
        observeMenuCommands()
        appState.setupLocalServicesIfNeeded()
        beginStartup()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menu commands (from the SwiftUI menu bar → AppDelegate)

    private func observeMenuCommands() {
        NotificationCenter.default.addObserver(
            forName: .lazyflowOpenSetup, object: nil, queue: .main
        ) { [weak self] _ in
            self?.presentOnboarding()
        }
        NotificationCenter.default.addObserver(
            forName: .lazyflowCheckForUpdates, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { UpdaterService.shared.checkForUpdates() }
        }
    }

    // MARK: - Startup / permissions

    /// First run — or a run where a required grant was revoked — opens the setup flow.
    /// Otherwise the global hotkey monitors start immediately.
    private func beginStartup() {
        permissions.refresh()
        if !OnboardingWindowController.hasOnboarded || !permissions.coreReady {
            presentOnboarding()
        } else {
            startHotkeys()
        }
    }

    func presentOnboarding() {
        guard onboardingController == nil else {
            onboardingController?.present()
            return
        }
        let controller = OnboardingWindowController(
            appState: appState,
            permissions: permissions
        ) { [weak self] in
            guard let self else { return }
            self.onboardingController = nil
            // Onboarding forced a Dock icon so its window could focus; restore the preference.
            AppState.applyActivationPolicy(showDockIcon: self.appState.showDockIcon)
            self.startHotkeys()
        }
        onboardingController = controller
        controller.present()
    }

    /// Starts the global hotkey monitors once. If Accessibility is missing, open the
    /// relevant Settings pane rather than leaving the app in a non-functional state.
    private func startHotkeys() {
        guard !hotkeysRunning else { return }
        do {
            try hotkeyManager.start()
            hotkeysRunning = true
        } catch {
            permissions.openSettings(.accessibility)
        }
    }

    // MARK: - Hotkeys

    private func configureHotkeyCallbacks() {
        hotkeyManager.onStartRecording  = { [weak self] in self?.appState.startRecording() }
        hotkeyManager.onStopRecording   = { [weak self] in self?.appState.stopRecording() }
        hotkeyManager.onCancelRecording = { [weak self] in self?.appState.cancelRecording() }
        hotkeyManager.onToggleModeActive = { [weak self] active in
            DispatchQueue.main.async { self?.appState.isToggleMode = active }
        }

        // When recording is cancelled via the UI cancel button, reset hotkey state too.
        appState.onRecordingCancelled = { [weak self] in
            DispatchQueue.main.async { self?.hotkeyManager.forceReset() }
        }
    }

    // MARK: - Overlay

    /// The overlay stays up for the whole pipeline, not just the recording part — transcription
    /// and cleanup can take a few seconds, and hiding at key-release left the user with no
    /// indication that anything was still happening.
    private func observeRecordingState() {
        appState.onRecordingModeChanged = { [weak self] mode in
            DispatchQueue.main.async {
                switch mode {
                case .recording, .processing: self?.overlay.show()
                case .idle:                   self?.overlay.hide()
                }
            }
        }
    }
}
