import AppKit

struct PopularApp: Identifiable, Hashable {
    let bundleIdentifier: String
    let displayName: String
    let systemImage: String
    let suggestedPreference: String

    var id: String { bundleIdentifier }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static let catalog: [PopularApp] = [
        .init(
            bundleIdentifier: "net.whatsapp.WhatsApp",
            displayName: "WhatsApp",
            systemImage: "bubble.left.and.bubble.right.fill",
            suggestedPreference: "short, lowercase, conversational messages with technical wording and no trailing period"
        ),
        .init(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            displayName: "Slack",
            systemImage: "number",
            suggestedPreference: "concise, friendly work messages with technical terms preserved and no unnecessary formality"
        ),
        .init(
            bundleIdentifier: "com.apple.MobileSMS",
            displayName: "Messages",
            systemImage: "message.fill",
            suggestedPreference: "very short, casual messages with natural contractions and no trailing period"
        ),
        .init(
            bundleIdentifier: "com.apple.mail",
            displayName: "Mail",
            systemImage: "envelope.fill",
            suggestedPreference: "clear, warm, professional email with complete sentences and restrained punctuation"
        ),
        .init(
            bundleIdentifier: "com.apple.Notes",
            displayName: "Notes",
            systemImage: "note.text",
            suggestedPreference: "clean structured notes, preserve line breaks, and turn dictated lists into bullets"
        ),
        .init(
            bundleIdentifier: "com.openai.codex",
            displayName: "Codex",
            systemImage: "terminal.fill",
            suggestedPreference: "direct technical instructions, preserve identifiers and paths, and avoid unnecessary prose"
        ),
        .init(
            bundleIdentifier: "com.apple.dt.Xcode",
            displayName: "Xcode",
            systemImage: "hammer.fill",
            suggestedPreference: "code-aware output that preserves identifiers, symbols, paths, flags, and exact casing"
        ),
        .init(
            bundleIdentifier: "com.mitchellh.ghostty",
            displayName: "Ghostty",
            systemImage: "apple.terminal.fill",
            suggestedPreference: "terminal-ready commands with exact flags, paths, casing, and no trailing punctuation"
        ),
    ]
}
