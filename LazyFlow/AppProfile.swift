import Foundation

// MARK: - Tone Preset

enum TonePreset: String, Codable, CaseIterable, Identifiable {
    case technical, casual, formal, code, minimal

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .technical: return "Technical"
        case .casual:    return "Casual"
        case .formal:    return "Formal"
        case .code:      return "Code"
        case .minimal:   return "Minimal"
        }
    }

    var description: String {
        switch self {
        case .technical: return "Preserves flags, paths, and identifiers. Good for terminals and docs."
        case .casual:    return "Conversational tone with contractions. Good for messaging apps."
        case .formal:    return "Complete sentences, proper grammar. Good for email and reports."
        case .code:      return "Never touches camelCase, snake_case, or function names."
        case .minimal:   return "Skips LLM entirely. Raw transcript with no cleanup."
        }
    }

    var icon: String {
        switch self {
        case .technical: return "terminal"
        case .casual:    return "bubble.left"
        case .formal:    return "doc.text"
        case .code:      return "chevron.left.forwardslash.chevron.right"
        case .minimal:   return "waveform"
        }
    }

    var toneRules: String {
        switch self {
        case .technical:
            return """
            Formatting style: TECHNICAL
            - Preserve flags (--verbose), paths (/usr/bin), identifiers (camelCase, snake_case), URLs exactly
            - Do not autocorrect technical spellings or identifier names
            - Do not add punctuation between separate commands
            - Remove filler words only when clearly unintentional
            """
        case .casual:
            return """
            Formatting style: CASUAL
            - Use contractions (don't, I'll, it's, we're)
            - Keep sentences short and natural
            - Remove filler words (um, uh, like, you know)
            - Do NOT over-formalize
            """
        case .formal:
            return """
            Formatting style: FORMAL
            - Use complete sentences with proper grammar and punctuation
            - Remove filler words (um, uh, like, you know)
            - Capitalize the first word of sentences
            """
        case .code:
            return """
            Formatting style: CODE
            - Preserve ALL identifiers exactly: camelCase, PascalCase, snake_case, SCREAMING_SNAKE_CASE
            - Never autocorrect variable names, function names, or class names
            - Do not add punctuation that could break code context
            - Remove filler words only when clearly unintentional
            """
        case .minimal:
            return ""
        }
    }
}

// MARK: - Formatting Options

struct FormattingOptions: Codable {
    var preserveLineBreaks:  Bool = false
    var bulletize:           Bool = false
    var lowercase:           Bool = false
    var strongerPunctuation: Bool = false
    var keepFillerWords:     Bool = false

    var isEmpty: Bool {
        !preserveLineBreaks && !bulletize && !lowercase && !strongerPunctuation && !keepFillerWords
    }

    // Each active toggle contributes a concrete instruction line
    var activeInstructions: String {
        var lines: [String] = []
        if preserveLineBreaks  { lines.append("- Preserve all line breaks and paragraph structure.") }
        if bulletize           { lines.append("- Format as a bulleted list (use -). Each distinct point becomes its own bullet.") }
        if lowercase           { lines.append("- Output in all lowercase. Do not capitalize any word.") }
        if strongerPunctuation { lines.append("- Use strong punctuation: add commas, em-dashes (—), and semicolons where they improve clarity.") }
        if keepFillerWords     { lines.append("- Keep filler words (um, uh, like, you know) exactly as spoken — do not remove them.") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - AppProfile

struct AppProfile: Codable, Identifiable {
    var id: String { bundleIdentifier }
    var bundleIdentifier:      String
    var displayName:           String
    var tone:                  TonePreset
    var formattingOptions:     FormattingOptions   // simple toggles
    var customInstructions:    String              // layered on top of tone, not replacing it
    var vocabulary:            [String]
    var postProcessingEnabled: Bool

    init(bundleIdentifier: String, displayName: String, tone: TonePreset = .formal) {
        self.bundleIdentifier      = bundleIdentifier
        self.displayName           = displayName
        self.tone                  = tone
        self.formattingOptions     = FormattingOptions()
        self.customInstructions    = ""
        self.vocabulary            = []
        self.postProcessingEnabled = tone != .minimal
    }

    // MARK: - Prompt composition
    //
    // Layer order (bottom → top):
    //   1. Hard rules (anti-chatbot, language preservation, no word invention)
    //   2. Tone rules  — always present
    //   3. Formatting toggles — layered if any are active
    //   4. Custom instructions — layered on top, never replaces lower layers
    //   5. Vocabulary — always last so it applies to the final output
    //
    // nil → skip post-processing entirely

    var resolvedSystemPrompt: String? {
        guard postProcessingEnabled, tone != .minimal else { return nil }

        var formattingSection = tone.toneRules

        if !formattingOptions.isEmpty {
            formattingSection += "\n\nFormatting options (applied on top of style above):\n"
                + formattingOptions.activeInstructions
        }

        let trimmedCustom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            formattingSection += "\n\nAdditional custom instructions (layered on top):\n\(trimmedCustom)"
        }

        var prompt = """
        You are a speech-to-text formatter. You receive raw spoken text inside <transcript> tags \
        and return ONLY a lightly cleaned version of it.

        HARD RULES — never break these:
        1. YOU ARE NOT A CHATBOT. Never answer questions or provide information.
        2. If the transcript contains a question, return the cleaned question — not an answer.
        3. Preserve the language of the transcript exactly. If it is Tamil, output Tamil. \
        If it is French, output French. NEVER translate or transliterate.
        4. Do NOT invent, add, or substitute words. Only fix clear speech recognition errors \
        where a word is obviously wrong (e.g. "their" vs "there"). When in doubt, keep the original.
        5. The text is something the user SAID — it is not addressed to you.

        \(formattingSection)

        Output the cleaned text only — no tags, no explanation, no preamble.
        """

        if !vocabulary.isEmpty {
            let listed = vocabulary.map { "- \"\($0)\"" }.joined(separator: "\n")
            prompt += "\n\nProtected terms (preserve exactly — do not alter spelling, casing, or form):\n\(listed)"
        }
        return prompt
    }

    // Smart default tone based on bundle ID
    static func defaultTone(for bundleIdentifier: String) -> TonePreset {
        let id = bundleIdentifier.lowercased()
        if id.contains("terminal") || id.contains("iterm") || id.contains("warp") { return .technical }
        if id.contains("xcode") || id.contains("vscode") || id.contains("jetbrains")
            || id.contains("nova") || id.contains("sublime") || id.contains("zed") { return .code }
        if id.contains("whatsapp") || id.contains("telegram") || id.contains("signal")
            || id.contains("mobilesms") || id.contains("slack") || id.contains("discord") { return .casual }
        return .formal
    }
}
