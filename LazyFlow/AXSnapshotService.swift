import AppKit
import ApplicationServices

@MainActor
enum AXSnapshotService {

    private static let interactiveRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXSecureTextField",
        "AXButton", "AXCheckBox", "AXRadioButton",
        "AXLink", "AXMenuItem", "AXMenuBarItem",
        "AXPopUpButton", "AXComboBox", "AXSlider",
    ]

    // Walk the AX tree of the given app and return all interactive elements with IDs.
    static func snapshot(for app: NSRunningApplication) -> [DetectedElement] {
        let pid = app.processIdentifier
        guard pid > 0 else { return [] }

        let appEl = AXUIElementCreateApplication(pid)
        let window = focusedWindow(appEl) ?? firstWindow(appEl)
        guard let win = window else { return [] }

        var elements: [DetectedElement] = []
        var counter = 0
        let deadline = Date().addingTimeInterval(2.0)
        walk(win, elements: &elements, counter: &counter, deadline: deadline)

        // Filter elements whose centres are off all visible screens.
        // Some apps (WhatsApp Catalyst, Electron) report AX positions in a
        // non-standard coordinate space, producing negative or extreme Y values
        // that are never on-screen. Removing them forces the agent to use
        // screenshot + click_coords instead of bogus element IDs.
        let allScreens = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
            .insetBy(dx: -50, dy: -50)   // 50pt tolerance for partially off-screen elements
        let onScreen = elements.filter { allScreens.contains(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY)) }
        return onScreen
    }

    // MARK: - Private

    private static func walk(
        _ el: AXUIElement,
        elements: inout [DetectedElement],
        counter: inout Int,
        deadline: Date,
        depth: Int = 0
    ) {
        guard depth < 12, counter < 250, Date() < deadline else { return }

        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef) == .success,
              let role = roleRef as? String else { return }

        if interactiveRoles.contains(role), let elem = makeElement(el, role: role, id: "elem_\(counter)") {
            elements.append(elem)
            counter += 1
        }

        // Also descend into web areas and groups that contain embedded content
        var childRef: CFTypeRef?
        let childAttr: CFString = (role == "AXWebArea" || role == "AXScrollArea")
            ? kAXChildrenAttribute as CFString
            : kAXChildrenAttribute as CFString
        guard AXUIElementCopyAttributeValue(el, childAttr, &childRef) == .success,
              let children = childRef as? [AXUIElement] else { return }

        for child in children.prefix(80) {
            walk(child, elements: &elements, counter: &counter, deadline: deadline, depth: depth + 1)
        }
    }

    private static func makeElement(_ el: AXUIElement, role: String, id: String) -> DetectedElement? {
        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posVal  = posRef,
              let sizeVal = sizeRef else { return nil }
        var pos  = CGPoint.zero
        var size = CGSize.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(posVal  as! AXValue, .cgPoint, &pos),
              // swiftlint:disable:next force_cast
              AXValueGetValue(sizeVal as! AXValue, .cgSize,  &size) else { return nil }
        let frame = CGRect(origin: pos, size: size)
        guard frame.width > 4, frame.height > 4 else { return nil }

        var enabledRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXEnabledAttribute as CFString, &enabledRef)
        let isEnabled = (enabledRef as? Bool) ?? true

        let label = [
            axStr(el, kAXTitleAttribute as CFString),
            axStr(el, kAXDescriptionAttribute as CFString),
            axStr(el, "AXPlaceholderValue" as CFString),
        ].compactMap { $0 }.first

        var valueRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valueRef)
        let value = valueRef as? String

        return DetectedElement(
            id:        id,
            type:      typeName(role),
            label:     label,
            value:     value,
            bounds:    frame,
            isEnabled: isEnabled
        )
    }

    private static func typeName(_ role: String) -> String {
        switch role {
        case "AXTextField", "AXSearchField": return "textField"
        case "AXTextArea":                   return "textArea"
        case "AXSecureTextField":            return "passwordField"
        case "AXButton":                     return "button"
        case "AXCheckBox":                   return "checkbox"
        case "AXRadioButton":                return "radioButton"
        case "AXLink":                       return "link"
        case "AXMenuItem", "AXMenuBarItem":  return "menuItem"
        case "AXPopUpButton":                return "dropdown"
        case "AXComboBox":                   return "comboBox"
        case "AXSlider":                     return "slider"
        default:                             return role.replacingOccurrences(of: "AX", with: "").lowercased()
        }
    }

    private static func axStr(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success,
              let s = ref as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func focusedWindow(_ app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &ref) == .success,
              let el = ref else { return nil }
        return (el as! AXUIElement) // swiftlint:disable:this force_cast
    }

    private static func firstWindow(_ app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let wins = ref as? [AXUIElement] else { return nil }
        return wins.first
    }
}
