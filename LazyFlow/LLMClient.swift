import Foundation

// Provider-aware HTTP client for dictation cleanup.
// Groq, OpenAI, Google, and custom endpoints use OpenAI-compatible chat
// completions; Anthropic uses its Messages API.
struct LLMClient {
    let config: LLMConfig

    struct ChatResponse {
        let content: String
        let finishReason: String?
    }

    func chat(
        messages: [[String: Any]],
        temperature: Double = 0.0,
        maxTokens: Int? = 1024
    ) async throws -> ChatResponse {
        if config.isAnthropic {
            let body = buildAnthropicBody(messages: messages, maxTokens: maxTokens ?? 1024)
            let data = try await postAnthropic(body: body)
            return try parseAnthropicResponse(data)
        }

        let body = buildOpenAICompatibleBody(
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens
        )
        let data = try await postOpenAICompatible(body: body)
        return try parseOpenAICompatibleResponse(data)
    }

    // MARK: - OpenAI-compatible API

    private func postOpenAICompatible(body: [String: Any]) async throws -> Data {
        let base = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        guard let endpoint = URL(string: "\(base)chat/completions") else {
            throw LLMError.badResponse
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try validate(data: data, response: response, host: endpoint.host)
    }

    private func buildOpenAICompatibleBody(
        messages: [[String: Any]],
        temperature: Double,
        maxTokens: Int?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
        ]
        if config.provider == .openai, config.model.hasPrefix("gpt-5.") {
            // GPT-5 reasoning models use an explicit low-latency reasoning setting for
            // deterministic transcript cleanup. Sampling parameters are intentionally omitted.
            body["reasoning_effort"] = "none"
        } else {
            body["temperature"] = temperature
        }
        if let maxTokens { body["max_tokens"] = maxTokens }
        if config.provider == .groq, config.model.hasPrefix("openai/gpt-oss-") {
            // Cleanup is deterministic rewriting, not a reasoning task. Keeping reasoning low
            // reduces time-to-output and prevents hidden reasoning from consuming the token cap.
            body["reasoning_effort"] = "low"
            body["include_reasoning"] = false
        }
        return body
    }

    private func parseOpenAICompatibleResponse(_ data: Data) throws -> ChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.badResponse
        }
        return ChatResponse(
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            finishReason: first["finish_reason"] as? String
        )
    }

    // MARK: - Anthropic Messages API

    private func postAnthropic(body: [String: Any]) async throws -> Data {
        let base = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        guard let endpoint = URL(string: "\(base)messages") else {
            throw LLMError.badResponse
        }
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        return try validate(data: data, response: response, host: endpoint.host)
    }

    private func buildAnthropicBody(
        messages: [[String: Any]],
        maxTokens: Int
    ) -> [String: Any] {
        var systemParts: [String] = []
        var conversation: [[String: Any]] = []

        for message in messages {
            guard let content = message["content"] as? String else { continue }
            if message["role"] as? String == "system" {
                systemParts.append(content)
            } else {
                let role = message["role"] as? String == "assistant" ? "assistant" : "user"
                conversation.append(["role": role, "content": content])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": maxTokens,
            "messages": conversation,
        ]
        if !systemParts.isEmpty {
            body["system"] = systemParts.joined(separator: "\n\n")
        }
        return body
    }

    private func parseAnthropicResponse(_ data: Data) throws -> ChatResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let blocks = json["content"] as? [[String: Any]] else {
            throw LLMError.badResponse
        }
        let text = blocks.compactMap { block in
            block["type"] as? String == "text" ? block["text"] as? String : nil
        }.joined()
        return ChatResponse(
            content: text.trimmingCharacters(in: .whitespacesAndNewlines),
            finishReason: json["stop_reason"] as? String
        )
    }

    // MARK: - Shared response validation

    private func validate(data: Data, response: URLResponse, host: String?) throws -> Data {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1

        if status == 429 {
            let message = String(data: data, encoding: .utf8) ?? ""
            let wait: Double
            if let match = message.range(of: #"in (\d+\.?\d*)s"#, options: .regularExpression) {
                let parts = message[match].components(separatedBy: .whitespaces)
                wait = (parts.first { $0.hasSuffix("s") }.flatMap { Double($0.dropLast()) } ?? 10) + 1
            } else {
                wait = 10
            }
            throw LLMError.rateLimited(retryAfter: wait)
        }

        guard status == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "empty body"
            let friendlyMessage: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                friendlyMessage = message
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let message = json["message"] as? String {
                friendlyMessage = message
            } else {
                friendlyMessage = raw
            }
            print("[LLM] ❌ HTTP \(status) from \(host ?? "?"): \(friendlyMessage)")
            throw LLMError.httpError(status, friendlyMessage)
        }
        return data
    }
}

enum LLMError: LocalizedError {
    case httpError(Int, String)
    case rateLimited(retryAfter: Double)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let message):
            "HTTP \(code): \(message)"
        case .rateLimited(let seconds):
            "Rate limited — retry in \(String(format: "%.0f", seconds))s"
        case .badResponse:
            "Unexpected API response"
        }
    }
}
