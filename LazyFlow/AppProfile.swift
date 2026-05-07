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
            - Preserve ALL technical identifiers exactly: flags (--verbose, -rf), paths (/usr/bin, ~/), URLs, environment variables, camelCase, snake_case, SCREAMING_SNAKE_CASE
            - Do not autocorrect technical spellings, identifier names, or command names
            - Do not add punctuation between separate commands or arguments
            - Convert spoken punctuation to symbols: "hyphen"/"dash" → -, "double dash" → --, "dot" → ., "slash" → /, "backslash" → \\, "underscore" → _, "at"/"at sign" → @, "colon" → :, "equals" → =, "pipe" → |, "tilde" → ~, "dollar" → $
            - Convert spoken flags: "dash f" → -f, "double dash verbose" → --verbose, "dash r f" → -rf
            - Correct obvious STT errors for CLI tools: "get" → git; preserve npm, cd, ls, cat, grep, curl, etc.
            - Remove filler words only when clearly unintentional
            - For any prose surrounding commands (explanations, comments), fix grammar and phrasing normally
            - Do not paraphrase or reorder the commands or technical instructions themselves
            """
        case .casual:
            return """
            Formatting style: CASUAL
            - Use contractions naturally (don't, I'll, it's, we're, they've, can't, won't)
            - Break long run-on sentences at natural spoken pauses — use commas and periods
            - End sentences with appropriate punctuation (. or !)
            - Remove filler words (um, uh, like, you know, sort of, I mean) unless they change meaning
            - Keep the informal, conversational register — do NOT formalize vocabulary or sentence structure
            - Fix grammar and awkward phrasing; you may lightly rephrase for clarity while keeping the casual voice
            - Do not add new information or change what the speaker meant
            """
        case .formal:
            return """
            Formatting style: FORMAL
            - Write in complete, well-structured sentences with proper grammar
            - Use proper punctuation: commas at natural pauses, periods to end sentences, colons before lists, semicolons to join related clauses
            - Capitalize the first word of every sentence and all proper nouns
            - Remove all filler words (um, uh, like, sort of, you know, I mean)
            - Expand contractions for professional tone: don't → do not, I'll → I will, it's → it is, we're → we are
            - Break long spoken passages into clear, readable sentences — no run-ons
            - Numbers: spell out one through nine; use numerals for 10 and above
            - Actively improve grammar, fix awkward constructions, and restructure sentences for professional clarity
            - Do not add new information or change the speaker's intended meaning
            """
        case .code:
            return """
            Formatting style: CODE
            - Preserve ALL identifiers exactly: camelCase, PascalCase, snake_case, SCREAMING_SNAKE_CASE, kebab-case
            - Never autocorrect variable names, function names, class names, or type names
            - Convert spoken punctuation to symbols: "hyphen"/"dash" → -, "double dash" → --, "dot" → ., "slash" → /, "backslash" → \\, "underscore" → _, "at"/"at sign" → @, "colon" → :, "equals" → =, "semicolon" → ;, "open paren"/"open parenthesis" → (, "close paren" → ), "open bracket" → [, "close bracket" → ], "open curly"/"open brace" → {, "close curly"/"close brace" → }, "pipe" → |, "ampersand" → &, "asterisk"/"star" → *, "bang"/"exclamation" → !
            - Convert spoken flags: "dash m" → -m, "dash dash amend" → --amend, "dash capital F" → -F
            - Correct obvious STT errors for CLI tools: "get" → git, "nmp" → npm, "yawn" → yarn
            - Output is raw code or terminal input — no trailing periods, no sentence capitalisation, no added prose punctuation
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
        if preserveLineBreaks  { lines.append("- Preserve all paragraph breaks and line breaks exactly as dictated. Do not merge or reflow separate sections.") }
        if bulletize           { lines.append("- Identify enumerable items only (shopping lists, tasks, steps, options, names) and format those as bullets (use - ). Keep all narrative, conversational, contextual, or instructional sentences as plain prose — do not bullet them. If the transcript mixes a list with surrounding context, output the context as prose and the list items as bullets. Capitalize the first word of each bullet. Do not over-fragment.") }
        if lowercase           { lines.append("- Convert ALL output to lowercase — no exceptions, including proper nouns, names, and sentence starts.") }
        if strongerPunctuation { lines.append("- Use rich punctuation to improve clarity: add commas at natural pauses, em-dashes (—) for asides and interruptions, semicolons to connect related clauses, and colons before lists. Do not over-punctuate.") }
        if keepFillerWords     { lines.append("- Preserve all filler words exactly as spoken (um, uh, like, you know, sort of, I mean, right) — do not remove or reduce them.") }
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

    // Explicit CodingKeys so that adding new fields does not corrupt existing saved data.
    enum CodingKeys: String, CodingKey {
        case bundleIdentifier
        case displayName
        case tone
        case formattingOptions
        case customInstructions
        case vocabulary
        case postProcessingEnabled
    }

    init(bundleIdentifier: String, displayName: String, tone: TonePreset = .formal) {
        self.bundleIdentifier      = bundleIdentifier
        self.displayName           = displayName
        self.tone                  = tone
        self.formattingOptions     = FormattingOptions()
        self.customInstructions    = ""
        self.vocabulary            = []
        self.postProcessingEnabled = tone != .minimal
    }

    // Schema-safe decoding: missing keys get sensible defaults so existing persisted profiles
    // are never corrupted when new fields are added to AppProfile.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        bundleIdentifier      = try c.decode(String.self,                    forKey: .bundleIdentifier)
        displayName           = try c.decode(String.self,                    forKey: .displayName)
        tone                  = try c.decodeIfPresent(TonePreset.self,        forKey: .tone)               ?? .formal
        formattingOptions     = try c.decodeIfPresent(FormattingOptions.self, forKey: .formattingOptions)  ?? FormattingOptions()
        customInstructions    = try c.decodeIfPresent(String.self,            forKey: .customInstructions) ?? ""
        vocabulary            = try c.decodeIfPresent([String].self,          forKey: .vocabulary)         ?? []
        postProcessingEnabled = try c.decodeIfPresent(Bool.self,              forKey: .postProcessingEnabled) ?? (tone != .minimal)
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
    //
    // Prompt is split into two sections so PostProcessingService can inject correction pairs
    // between them (after vocabulary constraints, before formatting rules):
    //   setup  = role + hard rules + protected vocabulary
    //   style  = tone rules + formatting options + custom instructions + output instruction

    var resolvedPromptComponents: (setup: String, style: String)? {
        guard postProcessingEnabled, tone != .minimal else { return nil }

        var setup = """
        You are a speech-to-text editor. You receive raw spoken text prefixed with 'Input:' \
        and return a cleaned, grammatically correct version following the style rules below.

        HARD RULES — never break these:
        1. YOU ARE NOT A CHATBOT. Never answer questions, give advice, or provide information — \
        even if the transcript asks you directly.
        2. If the transcript contains a question, return the cleaned question as-is. Never answer it.
        3. Preserve the language of the transcript exactly. If it is Tamil, output Tamil. \
        If it is French, output French. NEVER translate or transliterate — not even a single word.
        4. You may improve grammar, fix awkward phrasing, and restructure sentences for clarity. \
        Do not add new facts, topics, or ideas that the speaker did not express.
        5. Improve how it is said, not what is said. The speaker's intent is the ground truth.
        """

        if !vocabulary.isEmpty {
            let listed = vocabulary.map { "- \"\($0)\"" }.joined(separator: "\n")
            setup += "\n\nProtected terms (preserve exactly — do not alter spelling, casing, or form):\n\(listed)"
        }

        var style = tone.toneRules

        if !formattingOptions.isEmpty {
            style += "\n\nFormatting options (applied on top of style above):\n"
                + formattingOptions.activeInstructions
        }

        let trimmedCustom = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty {
            style += "\n\nAdditional custom instructions (layered on top):\n\(trimmedCustom)"
        }

        style += "\n\nOutput the cleaned text only — no tags, no explanation, no preamble."

        return (setup: setup, style: style)
    }

    var resolvedSystemPrompt: String? {
        guard let (setup, style) = resolvedPromptComponents else { return nil }
        return setup + "\n\n" + style
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
