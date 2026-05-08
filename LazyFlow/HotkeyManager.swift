import AppKit
import ApplicationServices

enum HotkeyError: LocalizedError {
    case accessibilityDenied
    var errorDescription: String? {
        "Accessibility permission required — go to System Settings → Privacy & Security → Accessibility, enable LazyFlow, then relaunch."
    }
}

final class HotkeyManager {
    // Right Option ⌥ — keyCode 61
    static let triggerKeyCode: UInt16 = 61

    var onStartRecording:   (() -> Void)?
    var onStopRecording:    (() -> Void)?
    var onCancelRecording:  (() -> Void)?
    var onToggleModeActive: ((Bool) -> Void)?

    // MARK: - State machine

    private enum State {
        case idle
        case pressed(at: Date)
        case holdRecording
        case awaitingDoubleTap
        case toggleRecording
    }

    private var state: State = .idle
    private var holdWorkItem:      DispatchWorkItem?
    private var doubleTapWorkItem: DispatchWorkItem?

    private static let holdThreshold:   TimeInterval = 0.15
    private static let doubleTapWindow: TimeInterval = 0.35

    // MARK: - NSEvent monitors

    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor:  Any?
    private var globalKeyMonitor:   Any?
    private var localKeyMonitor:    Any?

    func start() throws {
        guard AXIsProcessTrusted() else {
            let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts)
            throw HotkeyError.accessibilityDenied
        }

        globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
        }
        localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlags(event)
            return event
        }
        // Escape key cancels an in-progress recording (monitor only — does not consume the event)
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { DispatchQueue.main.async { self?.processEscape() } }
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { DispatchQueue.main.async { self?.processEscape() } }
            return event
        }
    }

    func stop() {
        [globalFlagsMonitor, localFlagsMonitor, globalKeyMonitor, localKeyMonitor]
            .compactMap { $0 }
            .forEach { NSEvent.removeMonitor($0) }
        globalFlagsMonitor = nil; localFlagsMonitor = nil
        globalKeyMonitor   = nil; localKeyMonitor   = nil
        cancelTimers()
        state = .idle
    }

    // Called externally when recording is cancelled via UI (cancel button) so state stays consistent
    func forceReset() {
        cancelTimers()
        if case .toggleRecording = state { onToggleModeActive?(false) }
        state = .idle
    }

    // MARK: - Event handling

    // Device-dependent mask for the physical right-Option key.
    // Using the device-independent .option flag would miss a right-Option release
    // when left-Option is simultaneously held, because .option stays set.
    private static let NX_DEVICERALTKEYMASK: UInt = 0x0000_0040

    private func handleFlags(_ event: NSEvent) {
        guard event.keyCode == Self.triggerKeyCode else { return }
        let isDown = (event.modifierFlags.rawValue & Self.NX_DEVICERALTKEYMASK) != 0
        DispatchQueue.main.async { [weak self] in self?.transition(isDown: isDown) }
    }

    private func transition(isDown: Bool) {
        switch state {

        case .idle:
            guard isDown else { return }
            state = .pressed(at: Date())
            schedule(&holdWorkItem, after: Self.holdThreshold) { [weak self] in
                guard case .pressed = self?.state else { return }
                self?.state = .holdRecording
                self?.onStartRecording?()
            }

        case .pressed:
            guard !isDown else { return }
            // Released before hold threshold → short tap, wait for double-tap
            holdWorkItem?.cancel(); holdWorkItem = nil
            state = .awaitingDoubleTap
            schedule(&doubleTapWorkItem, after: Self.doubleTapWindow) { [weak self] in
                guard case .awaitingDoubleTap = self?.state else { return }
                self?.state = .idle
            }

        case .awaitingDoubleTap:
            guard isDown else { return }
            // Second press within window → toggle mode
            doubleTapWorkItem?.cancel(); doubleTapWorkItem = nil
            state = .toggleRecording
            onToggleModeActive?(true)
            onStartRecording?()

        case .holdRecording:
            guard !isDown else { return }
            state = .idle
            onStopRecording?()

        case .toggleRecording:
            guard isDown else { return }
            // Any press stops toggle recording
            state = .idle
            onToggleModeActive?(false)
            onStopRecording?()
        }
    }

    private func processEscape() {
        switch state {
        case .holdRecording:
            cancelTimers()
            state = .idle
            onCancelRecording?()
        case .toggleRecording:
            cancelTimers()
            state = .idle
            onToggleModeActive?(false)
            onCancelRecording?()
        default:
            break
        }
    }

    // MARK: - Helpers

    private func cancelTimers() {
        holdWorkItem?.cancel();      holdWorkItem = nil
        doubleTapWorkItem?.cancel(); doubleTapWorkItem = nil
    }

    private func schedule(_ item: inout DispatchWorkItem?, after delay: TimeInterval, block: @escaping () -> Void) {
        let work = DispatchWorkItem(block: block)
        item = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
