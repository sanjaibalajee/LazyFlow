import Foundation

enum PostProcessingError: LocalizedError {
    case httpError(Int, String)
    var errorDescription: String? {
        switch self {
        case .httpError(let c, let m): return "Post-processing failed (\(c)): \(m)"
        }
    }
}

struct PostProcessingService {
    let config: LLMConfig

    // Provider-agnostic: the config carries provider/baseURL/model so the same
    // cleanup prompt works whether the backend speaks the OpenAI or Anthropic wire format.
    init(config: LLMConfig) {
        self.config = config
    }

    private var model: String { config.model }

    func process(rawTranscript: String,
                 profile: AppProfile,
                 corrections: [CorrectionEntry] = [],
                 kbContext: String? = nil,
                 focusContext: FocusContext? = nil) async throws -> String {
        guard let (setup, style) = profile.resolvedPromptComponents, !config.apiKey.isEmpty else {
            return rawTranscript
        }

        // Corrections are injected between setup (hard rules + vocabulary) and style (tone +
        // formatting). This ensures they are applied before formatting rules, not as an afterthought.
        var systemPrompt = setup
        if !corrections.isEmpty {
            let pairs = corrections
                .map { "- \"\($0.heard)\" → \"\($0.correct)\"" }
                .joined(separator: "\n")
            systemPrompt += "\n\nSpeech correction pairs (correct these speech recognition errors before applying formatting):\n\(pairs)"
        }

        var styleBlock = style

        if let focus = focusContext {
            // Smart Fill mode: override output to be a bare field value.
            // Append AFTER the regular style so these rules win.
            styleBlock += """


            SMART FILL — STRICT RULES (override everything above):
            You are populating \(focus.description).
            Output ONLY the exact text to insert into that field. Nothing else.
            - No field-name prefix (never output "First Name: value" — just output "value")
            - No punctuation added around the value
            - No explanation, preamble, or trailing text
            - For a "First Name" / "given name" / "forename" field → output the first name only
            - For a "Last Name" / "surname" / "family name" field → output the last name only
            - For a "Full Name" / "name" field → output the complete name
            - For "Email" / "email address" → output the email address only
            - For "Phone" / "mobile" / "tel" → output the phone number only
            - For "Company" / "organisation" / "employer" → output the company name only
            - For "Job Title" / "title" / "role" / "position" → output the job title only
            - For "Location" / "city" / "address" → output the location only
            - For "Website" / "URL" → output the URL only
            \(kbContext.map { "\n" + $0 } ?? "")
            Output the field value only. One line. No label.
            """
        } else if let kb = kbContext {
            styleBlock += "\n\nUser profile (use when relevant to the transcript):\n\(kb)"
        }

        systemPrompt += "\n\n" + styleBlock

        let userMessage = "Input:\n\n\(rawTranscript)"

        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] → \(model)")
#if LAZYFLOW_VERBOSE
        print("[LazyFlow] ── system prompt ──\n\(systemPrompt)\n── user message ──\n\(userMessage)")
#endif

        // Route through the shared multi-provider client so Anthropic (Messages API)
        // and OpenAI-compatible providers both work with the same cleanup prompt.
        let client = LLMClient(config: config)
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user",   "content": userMessage],
        ]

        let response: LLMClient.ChatResponse
        do {
            response = try await client.chat(
                messages: messages,
                temperature: 0.0,
                maxTokens: outputTokenLimit(for: rawTranscript)
            )
        } catch let err as LLMError {
            if case .httpError(let code, _) = err {
                throw PostProcessingError.httpError(code, "Provider returned \(code) — check your API key or try again.")
            }
            throw err
        }

        let result = response.content.isEmpty ? rawTranscript : response.content

        // Log metadata only — never log transcript content in any build
        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] \(result.split(separator: " ").count) words")
        return result
    }

    /// Cleanup output should be close in size to its input. A bounded, length-aware cap avoids
    /// paying for runaway reasoning or malformed responses while leaving ample room for languages
    /// whose tokenization is less compact than English.
    private func outputTokenLimit(for transcript: String) -> Int {
        let estimatedTokens = max(1, (transcript.utf8.count + 2) / 3)
        return min(2048, max(160, estimatedTokens * 2 + 64))
    }
}
