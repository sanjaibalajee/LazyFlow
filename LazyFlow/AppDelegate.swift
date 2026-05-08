import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState               = AppState()
    private let hotkeyManager  = HotkeyManager()
    private lazy var overlay   = RecordingOverlayController(appState: appState)

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestMicrophonePermission()
        setupHotkeys()
        observeRecordingState()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.onStartRecording  = { [weak self] in self?.appState.startRecording() }
        hotkeyManager.onStopRecording   = { [weak self] in self?.appState.stopRecording() }
        hotkeyManager.onCancelRecording = { [weak self] in self?.appState.cancelRecording() }
        hotkeyManager.onToggleModeActive = { [weak self] active in
            DispatchQueue.main.async { self?.appState.isToggleMode = active }
        }

        // When recording is cancelled via the UI cancel button, reset hotkey state too
        appState.onRecordingCancelled = { [weak self] in
            DispatchQueue.main.async { self?.hotkeyManager.forceReset() }
        }

        do {
            try hotkeyManager.start()
        } catch {
            showPermissionAlert(message: error.localizedDescription)
        }
    }

    // MARK: - Overlay

    private func observeRecordingState() {
        appState.onRecordingChanged = { [weak self] recording in
            DispatchQueue.main.async {
                if recording { self?.overlay.show() } else { self?.overlay.hide() }
            }
        }
    }

    // MARK: - Alert

    private func showPermissionAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "Permission Required"
            alert.informativeText = message
            alert.alertStyle      = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
        }
    }
}
