import Foundation

// Single OpenAI-compatible HTTP client used by both dictation and computer use.
// All providers (Groq, OpenAI, Google AI Studio) expose the same /chat/completions API.
// Anthropic uses a different format and is handled separately in the Anthropic path.

struct LLMClient {
    let config: LLMConfig

    // MARK: - Simple chat (dictation cleanup — no tools)

    struct ChatResponse {
        let content: String
        let finishReason: String?
    }

    func chat(
        messages: [[String: Any]],
        temperature: Double = 0.0,
        maxTokens: Int? = 1024
    ) async throws -> ChatResponse {
        let body = buildBody(
            messages: messages,
            tools: nil,
            toolChoice: nil,
            temperature: temperature,
            maxTokens: maxTokens
        )
        let data = try await post(body: body)
        return try parseChatResponse(data)
    }

    // MARK: - Chat with tools (computer use agent)

    struct ToolsResponse {
        let content: String?
        let toolCalls: [AgentToolCall]?
    }

    func chatWithTools(
        messages: [[String: Any]],
        tools: [[String: Any]],
        toolChoice: Any = "auto",
        temperature: Double = 0.1
    ) async throws -> ToolsResponse {
        let body = buildBody(
            messages: messages,
            tools: tools,
            toolChoice: toolChoice,
            temperature: temperature,
            maxTokens: nil
        )
        let data = try await post(body: body)
        return try parseToolsResponse(data)
    }

    // MARK: - HTTP

    private func post(body: [String: Any]) async throws -> Data {
        let base     = config.baseURL.hasSuffix("/") ? config.baseURL : config.baseURL + "/"
        let endpoint = URL(string: "\(base)chat/completions")!
        var req      = URLRequest(url: endpoint, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json",         forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1

        if status == 429 {
            let msg = String(data: data, encoding: .utf8) ?? ""
            let wait: Double
            if let m = msg.range(of: #"in (\d+\.?\d*)s"#, options: .regularExpression) {
                let sub = msg[m].components(separatedBy: .whitespaces)
                wait = (sub.first { $0.hasSuffix("s") }.flatMap { Double($0.dropLast()) } ?? 10) + 1
            } else { wait = 10 }
            throw LLMError.rateLimited(retryAfter: wait)
        }

        guard status == 200 else {
            let raw = String(data: data, encoding: .utf8) ?? "empty body"
            // Extract human-readable message from JSON error bodies (OpenAI / Google format)
            let friendlyMsg: String
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let errObj = json["error"] as? [String: Any],
                   let msg    = errObj["message"] as? String {
                    friendlyMsg = msg
                } else if let msg = json["message"] as? String {
                    friendlyMsg = msg
                } else {
                    friendlyMsg = raw
                }
            } else {
                friendlyMsg = raw
            }
            print("[LLM] ❌ HTTP \(status) from \(endpoint.host ?? "?"): \(friendlyMsg)")
            throw LLMError.httpError(status, friendlyMsg)
        }
        return data
    }

    // MARK: - Body construction

    private func buildBody(
        messages:    [[String: Any]],
        tools:       [[String: Any]]?,
        toolChoice:  Any?,
        temperature: Double,
        maxTokens:   Int?
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model":       config.model,
            "messages":    messages,
            "temperature": temperature,
        ]
        if let mt = maxTokens { body["max_tokens"] = mt }
        if let t  = tools, !t.isEmpty {
            body["tools"] = t
            body["tool_choice"] = toolChoice ?? "auto"
        }
        return body
    }

    // MARK: - Response parsing

    private func parseChatResponse(_ data: Data) throws -> ChatResponse {
        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String
        else { throw LLMError.badResponse }
        let reason = (first["finish_reason"] as? String)
        return ChatResponse(content: content.trimmingCharacters(in: .whitespacesAndNewlines),
                            finishReason: reason)
    }

    private func parseToolsResponse(_ data: Data) throws -> ToolsResponse {
        guard let json    = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first   = choices.first,
              let message = first["message"] as? [String: Any]
        else { throw LLMError.badResponse }

        let content   = message["content"] as? String
        var toolCalls: [AgentToolCall]? = nil

        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            toolCalls = rawCalls.compactMap { raw in
                guard let id    = raw["id"] as? String,
                      let fn    = raw["function"] as? [String: Any],
                      let name  = fn["name"] as? String,
                      let argsS = fn["arguments"] as? String,
                      let argsD = argsS.data(using: .utf8),
                      let argsJ = try? JSONSerialization.jsonObject(with: argsD) as? [String: Any]
                else { return nil }
                var args: [String: String] = [:]
                for (k, v) in argsJ {
                    if let s = v as? String       { args[k] = s }
                    else if let n = v as? NSNumber { args[k] = n.stringValue }
                }
                return AgentToolCall(id: id, name: name, arguments: args)
            }
        }
        return ToolsResponse(content: content, toolCalls: toolCalls)
    }
}

// MARK: - Errors

enum LLMError: LocalizedError {
    case httpError(Int, String)
    case rateLimited(retryAfter: Double)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .httpError(let c, let m):    "HTTP \(c): \(m)"
        case .rateLimited(let s):         "Rate limited — retry in \(String(format: "%.0f", s))s"
        case .badResponse:                "Unexpected API response"
        }
    }

    var isRateLimited: Bool {
        if case .rateLimited = self { return true }
        return false
    }

    var retryAfter: Double {
        if case .rateLimited(let s) = self { return s }
        return 0
    }
}

// MARK: - Retry helper

extension LLMClient {
    /// Calls the closure up to 4 times, auto-waiting on rate-limit responses.
    func withRetry<T>(_ work: () async throws -> T) async throws -> T {
        for attempt in 0..<4 {
            do {
                return try await work()
            } catch let err as LLMError where err.isRateLimited {
                let wait = err.retryAfter + Double(attempt) * 2
                print("[LLM] ⏳ rate limited — waiting \(String(format: "%.1f", wait))s")
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
        throw LLMError.rateLimited(retryAfter: 0)
    }
}
