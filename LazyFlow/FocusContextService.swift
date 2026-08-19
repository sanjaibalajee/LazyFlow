import AppKit
import ApplicationServices

// MARK: - Model

struct FocusContext {
    let appName: String
    let bundleId: String
    let role: String?
    let label: String?
    let placeholder: String?

    // Human-readable summary for LLM injection, e.g. "the "Subject" field in Mail"
    nonisolated var description: String {
        var parts: [String] = []

        if let l = label, !l.isEmpty {
            parts.append("the \"\(l)\" field")
        } else if let friendly = friendlyRole {
            parts.append("a \(friendly) field")
        }

        parts.append("in \(appName)")
        return parts.joined(separator: " ")
    }

    /// Long title-cased text is normally a cleanup failure, except when the user is genuinely
    /// filling a title/headline field.
    nonisolated var allowsTitleCase: Bool {
        [label, placeholder]
            .compactMap { $0?.lowercased() }
            .contains { $0.contains("title") || $0.contains("headline") }
    }

    nonisolated private var friendlyRole: String? {
        switch role {
        case "AXTextField":       "text input"
        case "AXTextArea":        "multi-line text"
        case "AXSearchField":     "search"
        case "AXSecureTextField": "password"
        default:                  nil
        }
    }
}

// MARK: - Service

@MainActor
enum FocusContextService {
    private static let textRoles: Set<String> = [
        "AXTextField", "AXTextArea", "AXSearchField", "AXSecureTextField",
    ]

    /// Returns context for the currently focused text element in the given app.
    /// Returns nil if the focused element is not a text field or AX is unavailable.
    static func capture(for app: NSRunningApplication) -> FocusContext? {
        let pid = app.processIdentifier
        guard pid > 0 else { return nil }

        let appEl = AXUIElementCreateApplication(pid)

        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let el = focused, CFGetTypeID(el) == AXUIElementGetTypeID() else { return nil }
        let element = el as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String

        guard let r = role, textRoles.contains(r) else { return nil }

        let label = firstNonEmpty(
            axString(element, kAXTitleAttribute as CFString),
            axString(element, kAXDescriptionAttribute as CFString)
        )
        let placeholder = axString(element, "AXPlaceholderValue" as CFString)

        return FocusContext(
            appName: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? "",
            role: role,
            label: label,
            placeholder: placeholder
        )
    }

    private static func axString(_ el: AXUIElement, _ attr: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, attr, &ref) == .success,
              let s = ref as? String, !s.isEmpty else { return nil }
        return s
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        values.first { $0 != nil && !($0!.isEmpty) } ?? nil
    }
}
