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
    let apiKey:  String
    let baseURL: String
    let model:   String

    init(apiKey: String,
         baseURL: String = "https://api.groq.com/openai/v1",
         model: String   = "openai/gpt-oss-20b") {
        self.apiKey  = apiKey
        self.baseURL = baseURL
        self.model   = model
    }

    func process(rawTranscript: String,
                 profile: AppProfile,
                 corrections: [CorrectionEntry] = []) async throws -> String {
        guard let (setup, style) = profile.resolvedPromptComponents, !apiKey.isEmpty else {
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
        systemPrompt += "\n\n" + style

        let userMessage = "Input:\n\n\(rawTranscript)"

        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] → \(model)")
#if LAZYFLOW_VERBOSE
        print("[LazyFlow] ── system prompt ──\n\(systemPrompt)\n── user message ──\n\(userMessage)")
#endif

        let endpoint = URL(string: "\(baseURL)/chat/completions")!
        var request  = URLRequest(url: endpoint, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ],
            "temperature": 0.0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1

        print("[LazyFlow] 🤖 HTTP \(statusCode)")
#if LAZYFLOW_VERBOSE
        print("[LazyFlow] ── raw response ──\n\(String(data: data, encoding: .utf8) ?? "<binary>")")
#endif

        if statusCode != 200 {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
#if DEBUG
            print("[LazyFlow] 🤖 Post-processing error body: \(msg)")
#endif
            throw PostProcessingError.httpError(statusCode, "Provider returned \(statusCode) — check your API key or try again.")
        }

        struct Msg:      Decodable { let content: String }
        struct Choice:   Decodable { let message: Msg; let finish_reason: String? }
        struct Response: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let choice  = decoded.choices.first

        let result = choice?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTranscript

        // Log metadata only — never log transcript content in any build
        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] \(result.split(separator: " ").count) words")
        return result
    }
}
