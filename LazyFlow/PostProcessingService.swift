import Foundation

enum PostProcessingError: LocalizedError {
    case httpError(Int, String)
    case truncated               // model hit token limit — response may be partial
    var errorDescription: String? {
        switch self {
        case .httpError(let c, let m): return "Post-processing failed (\(c)): \(m)"
        case .truncated:               return "Cleanup response was truncated — raw transcript used."
        }
    }
}

struct PostProcessingService {
    let apiKey:  String
    let baseURL: String
    let model:   String

    init(apiKey: String,
         baseURL: String = "https://api.groq.com/openai/v1",
         model: String   = "llama-3.1-8b-instant") {
        self.apiKey  = apiKey
        self.baseURL = baseURL
        self.model   = model
    }

    func process(rawTranscript: String, profile: AppProfile) async throws -> String {
        guard let systemPrompt = profile.resolvedSystemPrompt, !apiKey.isEmpty else {
            return rawTranscript
        }

        let userMessage = "<transcript>\n\(rawTranscript)\n</transcript>"

        // Word count * ~1.5 token/word, doubled for headroom, floored at 256
        let estimatedTokens = max(256, rawTranscript.split(separator: " ").count * 3)

        // Metadata-only log in all builds. Full prompt/transcript dump requires
        // -DLAZYFLOW_VERBOSE set in Other Swift Flags (never enable in production).
        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] ~\(estimatedTokens) tokens → \(model)")
#if LAZYFLOW_VERBOSE
        print("[LazyFlow] ── system prompt ──\n\(systemPrompt)\n── user message ──\n\(userMessage)")
#endif

        let endpoint = URL(string: "\(baseURL)/chat/completions")!
        var request  = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json",  forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user",   "content": userMessage]
            ],
            "max_tokens":  estimatedTokens,
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
            throw PostProcessingError.httpError(statusCode, msg)
        }

        struct Msg:      Decodable { let content: String }
        struct Choice:   Decodable { let message: Msg; let finish_reason: String? }
        struct Response: Decodable { let choices: [Choice] }

        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let choice  = decoded.choices.first

        // If the model was cut off by the token limit, fall back to raw to avoid partial output
        if choice?.finish_reason == "length" {
            print("[LazyFlow] ⚠️ Cleanup truncated (hit token limit) — falling back to raw transcript")
            throw PostProcessingError.truncated
        }

        let result = choice?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? rawTranscript

        // Log metadata only — never log transcript content in any build
        print("[LazyFlow] 🤖 \(profile.displayName) [\(profile.tone.displayName)] \(result.split(separator: " ").count) words")
        return result
    }
}
