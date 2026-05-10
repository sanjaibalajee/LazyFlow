import AppKit
import ApplicationServices

@MainActor
enum AgentInputDriver {

    // MARK: - Click

    static func click(at point: CGPoint) {
        guard let down = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let up = CGEvent(
            mouseEventSource: nil,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }

        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        up.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.06)
    }

    // MARK: - Double Click

    static func doubleClick(at point: CGPoint) {
        let src = CGEventSource(stateID: .hidSystemState)
        for clickState in 1...2 {
            guard let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                                     mouseCursorPosition: point, mouseButton: .left),
                  let up   = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                                     mouseCursorPosition: point, mouseButton: .left)
            else { return }
            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up.setIntegerValueField(.mouseEventClickState,   value: Int64(clickState))
            down.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.015)
            up.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: clickState == 1 ? 0.10 : 0.05)
        }
    }

    // MARK: - Type

    static func type(text: String) {
        // Try AX setValue on the currently focused element first
        if let app = NSWorkspace.shared.frontmostApplication {
            let appEl = AXUIElementCreateApplication(app.processIdentifier)
            var focRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focRef) == .success,
               let el = focRef {
                // swiftlint:disable:next force_cast
                let result = AXUIElementSetAttributeValue(el as! AXUIElement, kAXValueAttribute as CFString, text as CFTypeRef)
                if result == .success { return }
            }
        }

        // Fallback: clipboard paste (preserves existing clipboard contents)
        let pb   = NSPasteboard.general
        let prev = pb.string(forType: .string)
        pb.clearContents()
        pb.setString(text, forType: .string)
        Thread.sleep(forTimeInterval: 0.05)

        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.10)

        if let prev { pb.clearContents(); pb.setString(prev, forType: .string) }
    }

    // MARK: - Key press

    static func pressKey(_ name: String) {
        let (code, flags) = keyCode(for: name)
        guard code != 0xFFFF else { return }
        let src  = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)
        down?.flags = flags; up?.flags = flags
        down?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.015)
        up?.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.05)
    }

    // MARK: - Scroll

    static func scroll(direction: String, lines: Int) {
        let delta = Int32(direction == "down" ? -lines : lines)
        let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 1,
            wheel1: delta,
            wheel2: 0,
            wheel3: 0
        )
        event?.post(tap: .cghidEventTap)
    }

    // MARK: - Helpers

    private static func keyCode(for name: String) -> (CGKeyCode, CGEventFlags) {
        switch name.lowercased() {
        // Basic keys
        case "return", "enter":      return (0x24, [])
        case "tab":                  return (0x30, [])
        case "escape", "esc":        return (0x35, [])
        case "space":                return (0x31, [])
        case "delete", "backspace":  return (0x33, [])
        case "forward_delete":       return (0x75, [])
        case "up":                   return (0x7E, [])
        case "down":                 return (0x7D, [])
        case "left":                 return (0x7B, [])
        case "right":                return (0x7C, [])
        case "home":                 return (0x73, [])
        case "end":                  return (0x77, [])
        case "pageup":               return (0x74, [])
        case "pagedown":             return (0x79, [])
        // Cmd combos — text editing
        case "cmd+a":                return (0x00, .maskCommand)
        case "cmd+c":                return (0x08, .maskCommand)
        case "cmd+v":                return (0x09, .maskCommand)
        case "cmd+x":                return (0x07, .maskCommand)
        case "cmd+z":                return (0x06, .maskCommand)
        case "cmd+shift+z":          return (0x06, [.maskCommand, .maskShift])
        case "cmd+s":                return (0x01, .maskCommand)
        case "cmd+f":                return (0x03, .maskCommand)
        // Cmd combos — app/window/tab management
        case "cmd+tab":              return (0x30, .maskCommand)   // switch app
        case "cmd+`", "cmd+backtick": return (0x32, .maskCommand)  // switch window same app
        case "cmd+shift+tab":        return (0x30, [.maskCommand, .maskShift])
        case "cmd+w":                return (0x0D, .maskCommand)   // close window/tab
        case "cmd+n":                return (0x2D, .maskCommand)   // new window
        case "cmd+t":                return (0x11, .maskCommand)   // new tab
        case "cmd+r":                return (0x0F, .maskCommand)   // reload
        case "cmd+l":                return (0x25, .maskCommand)   // address bar
        case "cmd+q":                return (0x0C, .maskCommand)   // quit app
        // Cmd combos — navigation
        case "cmd+left":             return (0x7B, .maskCommand)
        case "cmd+right":            return (0x7C, .maskCommand)
        case "cmd+up":               return (0x7E, .maskCommand)
        case "cmd+down":             return (0x7D, .maskCommand)
        case "opt+left":             return (0x7B, .maskAlternate)
        case "opt+right":            return (0x7C, .maskAlternate)
        default:                     return (0xFFFF, [])
        }
    }
}
