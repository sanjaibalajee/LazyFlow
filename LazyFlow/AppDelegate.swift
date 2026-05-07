import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState          = AppState()
    private let hotkeyManager = HotkeyManager()
    private lazy var overlay  = RecordingOverlayController(appState: appState)

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
        hotkeyManager.onKeyDown = { [weak self] in self?.appState.startRecording() }
        hotkeyManager.onKeyUp   = { [weak self] in self?.appState.stopRecording() }

        do {
            try hotkeyManager.start()
        } catch {
            showPermissionAlert(message: error.localizedDescription)
        }
    }

    // MARK: - Overlay (uses callback instead of Combine — works with @Observable)

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
