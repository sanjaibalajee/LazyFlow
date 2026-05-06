import Cocoa

enum HotkeyError: LocalizedError {
    case accessibilityDenied
    case tapCreationFailed
    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Accessibility permission required — go to System Settings → Privacy & Security → Accessibility, enable LazyFlow, then relaunch."
        case .tapCreationFailed:
            return "Failed to create keyboard event tap. Toggle Accessibility off and on in System Settings, then relaunch."
        }
    }
}

private func tapCallback(
    _ proxy: CGEventTapProxy,
    _ type: CGEventType,
    _ event: CGEvent,
    _ refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passRetained(event) }
    return Unmanaged<HotkeyManager>.fromOpaque(refcon)
        .takeUnretainedValue()
        .handle(type: type, event: event)
}

final class HotkeyManager {
    // Right Option ⌥ — keyCode 61
    static let triggerKeyCode: Int64 = 61

    var onKeyDown: (() -> Void)?
    var onKeyUp:   (() -> Void)?

    private var tap:      CFMachPort?
    private var source:   CFRunLoopSource?
    private var keyIsDown = false

    func start() throws {
        guard AXIsProcessTrusted() else {
            let opts: NSDictionary = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
            AXIsProcessTrustedWithOptions(opts)
            throw HotkeyError.accessibilityDenied
        }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue)

        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: tapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { throw HotkeyError.tapCreationFailed }

        tap    = eventTap
        let rs = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        source = rs
        CFRunLoopAddSource(CFRunLoopGetMain(), rs, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let t = tap    { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil; source = nil
    }

    func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
            return nil
        }

        guard type == .flagsChanged,
              event.getIntegerValueField(.keyboardEventKeycode) == Self.triggerKeyCode
        else { return Unmanaged.passRetained(event) }

        let nowDown = event.flags.contains(.maskAlternate)
        if nowDown && !keyIsDown {
            keyIsDown = true
            DispatchQueue.main.async { [weak self] in self?.onKeyDown?() }
        } else if !nowDown && keyIsDown {
            keyIsDown = false
            DispatchQueue.main.async { [weak self] in self?.onKeyUp?() }
        }
        return Unmanaged.passRetained(event)
    }
}
