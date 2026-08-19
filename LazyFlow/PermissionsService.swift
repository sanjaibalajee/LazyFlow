import AppKit
import AVFoundation
import ApplicationServices
import Observation

private final class WeakPermissionsServiceBox: @unchecked Sendable {
    weak var value: PermissionsService?

    init(_ value: PermissionsService) {
        self.value = value
    }
}

// Central permission state and request flow for the two grants dictation needs.
// The first request triggers the macOS prompt; later requests open the relevant
// System Settings pane. Polling keeps onboarding status in sync while settings are open.
@MainActor
@Observable
final class PermissionsService {
    enum Kind: String, CaseIterable, Identifiable {
        case accessibility
        case microphone

        nonisolated var id: String { rawValue }

        var title: String {
            switch self {
            case .accessibility: "Accessibility"
            case .microphone:    "Microphone"
            }
        }

        var systemImage: String {
            switch self {
            case .accessibility: "hand.tap"
            case .microphone:    "mic"
            }
        }

        var rationale: String {
            switch self {
            case .accessibility:
                "Lets LazyFlow detect the global hotkey and paste text at your cursor. Required."
            case .microphone:
                "Lets LazyFlow hear you when you dictate. Required."
            }
        }

        var settingsURL: URL {
            let anchor = switch self {
            case .accessibility: "Privacy_Accessibility"
            case .microphone:    "Privacy_Microphone"
            }
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        }
    }

    // MARK: - Published status

    private(set) var accessibility = false
    private(set) var microphone    = false

    func isGranted(_ kind: Kind) -> Bool {
        switch kind {
        case .accessibility: accessibility
        case .microphone:    microphone
        }
    }

    var coreReady: Bool { accessibility && microphone }

    // MARK: - Internal state

    private var promptedThisLaunch: Set<Kind> = []
    private var timer: Timer?
    private var onChange: (() -> Void)?
    private var accessibilityGuideController: AccessibilityPermissionGuideController?
    private var dismissGuideWhenAccessibilityIsGranted = false

    // MARK: - Status checks

    func refresh() {
        accessibility = AXIsProcessTrusted()
        microphone = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    // MARK: - Request flow

    func request(_ kind: Kind) {
        refresh()
        guard !isGranted(kind) else { return }

        switch kind {
        case .microphone:
            if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
                let service = WeakPermissionsServiceBox(self)
                AVCaptureDevice.requestAccess(for: .audio) { _ in
                    Task { @MainActor in service.value?.refresh() }
                }
            } else {
                openSettings(kind)
            }

        case .accessibility:
            showAccessibilityGuide()
            if promptedThisLaunch.insert(kind).inserted {
                let opts = [
                    kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
                ] as CFDictionary
                _ = AXIsProcessTrustedWithOptions(opts)
            } else {
                openSettings(kind)
            }
        }
    }

    func openSettings(_ kind: Kind) {
        NSWorkspace.shared.open(kind.settingsURL)
    }

    /// Reveals LazyFlow in Finder so it can be dragged into the Accessibility list
    /// if macOS fails to add it automatically.
    func revealAppInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
    }

    func showAccessibilityGuide() {
        if let accessibilityGuideController {
            accessibilityGuideController.present()
            return
        }

        // A guide opened while permission is missing should disappear as soon as the
        // user succeeds. The explicit fallback link remains previewable after a grant.
        dismissGuideWhenAccessibilityIsGranted = !accessibility
        let controller = AccessibilityPermissionGuideController(
            onOpenSettings: { [weak self] in self?.openSettings(.accessibility) },
            onRevealInFinder: { [weak self] in self?.revealAppInFinder() },
            onClose: { [weak self] in
                self?.accessibilityGuideController = nil
                self?.dismissGuideWhenAccessibilityIsGranted = false
            }
        )
        accessibilityGuideController = controller
        controller.present()
    }

    // MARK: - Polling

    func startPolling(onChange: @escaping () -> Void) {
        self.onChange = onChange
        refresh()
        timer?.invalidate()
        let service = WeakPermissionsServiceBox(self)
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            Task { @MainActor in service.value?.poll() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() {
        let before = (accessibility, microphone)
        refresh()
        if accessibility && dismissGuideWhenAccessibilityIsGranted {
            accessibilityGuideController?.close()
        }
        if before != (accessibility, microphone) {
            onChange?()
        }
    }
}
