import AppKit
import Carbon.HIToolbox

// Robust text insertion into whatever app was frontmost when recording started.
//
// Two strategies (user-selectable):
//   • clipboardPaste — write the pasteboard and synthesize ⌘V, then restore the user's
//     clipboard. The ⌘V keystroke uses a *layout-aware* key code so it works on Dvorak,
//     AZERTY, Colemak, etc. — a plain hard-coded 0x09 ("v" on QWERTY) pastes the wrong key
//     on those layouts. This is the reliable default: it works in secure fields and Electron
//     apps that ignore synthesized characters.
//   • unicodeTyping — synthesize the characters directly via CGEvent unicode strings, never
//     touching the pasteboard. Cleaner (your clipboard is untouched) but some apps ignore
//     synthetic unicode input, so it's opt-in.
enum InsertionMode: String, CaseIterable, Identifiable {
    case clipboardPaste
    case unicodeTyping

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .clipboardPaste: "Clipboard paste (most compatible)"
        case .unicodeTyping:  "Type directly (leaves clipboard untouched)"
        }
    }
}

enum TextInjector {

    /// Inserts `text` into `targetApp`.
    static func insert(
        _ text: String,
        into targetApp: NSRunningApplication?,
        mode: InsertionMode,
        pressEnter: Bool = false
    ) {
        guard !text.isEmpty || pressEnter else { return }
        targetApp?.activate()

        // Give activation and the hotkey release a beat to land before sending keystrokes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            if !text.isEmpty {
                switch mode {
                case .clipboardPaste: pasteViaClipboard(text)
                case .unicodeTyping:  typeUnicode(text)
                }
            }
            if pressEnter {
                // Let the destination consume pasted/typed text before submitting it.
                DispatchQueue.main.asyncAfter(deadline: .now() + (text.isEmpty ? 0 : 0.05)) {
                    postReturn()
                }
            }
        }
    }

    // MARK: - Clipboard paste

    private static func pasteViaClipboard(_ text: String) {
        let pb = NSPasteboard.general
        let saved = ClipboardSnapshot(pb)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let changeCountAfterWrite = pb.changeCount

        postCommandV()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            // Only restore if nothing else wrote to the clipboard since our write —
            // if the count changed, the user copied something new; leave it alone.
            guard pb.changeCount == changeCountAfterWrite else { return }
            saved.restore(to: pb)
        }
    }

    private static func postCommandV() {
        let src  = CGEventSource(stateID: .hidSystemState)
        let vKey = KeyboardLayout.keyCode(for: "v") ?? 0x09  // 0x09 = "v" on QWERTY
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private static func postReturn() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x24, keyDown: false)
        down?.flags = []
        up?.flags = []
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Unicode typing (clipboard-free)

    private static func typeUnicode(_ text: String) {
        let src   = CGEventSource(stateID: .hidSystemState)
        let units = Array(text.utf16)
        // keyboardSetUnicodeString is reliable in small batches; chunk to stay well under limits.
        let chunkSize = 20
        var i = 0
        while i < units.count {
            let chunk = Array(units[i..<min(i + chunkSize, units.count)])
            let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true)
            let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            down?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            i += chunkSize
        }
    }
}

// MARK: - Layout-aware key codes

private enum KeyboardLayout {
    /// Finds the virtual key code that produces `character` on the *current* keyboard layout.
    /// Returns nil if the layout can't be read (caller falls back to the QWERTY code).
    static func keyCode(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(layoutPtr).takeUnretainedValue()
        let target = String(character)

        return (CFDataGetBytePtr(layoutData)).withMemoryRebound(
            to: UCKeyboardLayout.self, capacity: 1
        ) { keyboardLayout -> CGKeyCode? in
            let kbdType = UInt32(LMGetKbdType())
            for code in 0..<CGKeyCode(128) {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    keyboardLayout,
                    UInt16(code),
                    UInt16(kUCKeyActionDown),
                    0,                     // no modifiers
                    kbdType,
                    OptionBits(kUCKeyTranslateNoDeadKeysBit),
                    &deadKeyState,
                    chars.count,
                    &length,
                    &chars
                )
                if status == noErr, length > 0,
                   String(utf16CodeUnits: chars, count: length) == target {
                    return code
                }
            }
            return nil
        }
    }
}

// MARK: - Clipboard snapshot (preserves ALL pasteboard types, not just strings)

struct ClipboardSnapshot {
    private struct Item {
        let types: [NSPasteboard.PasteboardType]
        let data:  [NSPasteboard.PasteboardType: Data]
    }
    private let items: [Item]

    init(_ pb: NSPasteboard) {
        items = (pb.pasteboardItems ?? []).map { raw in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in raw.types { data[type] = raw.data(forType: type) }
            return Item(types: raw.types, data: data)
        }
    }

    func restore(to pb: NSPasteboard) {
        pb.clearContents()
        let restored: [NSPasteboardItem] = items.map { saved in
            let item = NSPasteboardItem()
            for type in saved.types {
                if let d = saved.data[type] { item.setData(d, forType: type) }
            }
            return item
        }
        if !restored.isEmpty { pb.writeObjects(restored) }
    }
}
