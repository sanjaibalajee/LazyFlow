import Foundation

enum GroqServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            "Add a Groq API key in Settings or switch this step to Apple On-Device."
        case .invalidResponse:
            "Groq returned an unreadable response."
        case .httpError(let status, let message):
            "Groq request failed (\(status)): \(message)"
        }
    }
}

struct GroqService: Sendable {
    private let baseURL = URL(string: "https://api.groq.com/openai/v1")!

    func validateAPIKey(_ apiKey: String) async throws {
        let request = try authorizedRequest(
            path: "models",
            apiKey: apiKey,
            method: "GET"
        )
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw GroqServiceError.httpError(
                (response as? HTTPURLResponse)?.statusCode ?? -1,
                "Check the key and try again."
            )
        }
    }

    func transcribe(
        recordingAt url: URL,
        apiKey: String,
        model: GroqSpeechModel
    ) async throws -> String {
        let key = try requireKey(apiKey)
        let boundary = "LazyFlow-\(UUID().uuidString)"
        var request = try authorizedRequest(
            path: "audio/transcriptions",
            apiKey: key,
            method: "POST"
        )
        request.timeoutInterval = 60
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type"
        )
        request.httpBody = try multipartBody(
            recordingAt: url,
            model: model.rawValue,
            boundary: boundary
        )

        let data = try await perform(request)
        struct Response: Decodable { let text: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw GroqServiceError.invalidResponse
        }
        return response.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refine(
        _ transcript: String,
        tone: MobileTone,
        apiKey: String,
        model: GroqRewriteModel
    ) async throws -> String {
        let key = try requireKey(apiKey)
        var request = try authorizedRequest(
            path: "chat/completions",
            apiKey: key,
            method: "POST"
        )
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model.rawValue,
            "messages": [
                ["role": "system", "content": tone.editingInstructions],
                ["role": "user", "content": transcript]
            ],
            "temperature": 0,
            "max_completion_tokens": 1_024,
            "reasoning_effort": "low",
            "include_reasoning": false
        ]
        if tone == .verbatim {
            body["temperature"] = 0
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw GroqServiceError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func authorizedRequest(
        path: String,
        apiKey: String,
        method: String
    ) throws -> URLRequest {
        let key = try requireKey(apiKey)
        let url = baseURL.appending(path: path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        return request
    }

    private func requireKey(_ key: String) throws -> String {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { throw GroqServiceError.missingAPIKey }
        return value
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            let message = friendlyError(from: data)
            throw GroqServiceError.httpError(status, message)
        }
        return data
    }

    private func friendlyError(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return "Check your key, selected model, and network connection."
    }

    private func multipartBody(
        recordingAt url: URL,
        model: String,
        boundary: String
    ) throws -> Data {
        var body = Data()
        let lineBreak = "\r\n"

        func append(_ text: String) {
            body.append(Data(text.utf8))
        }

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"model\"\(lineBreak)\(lineBreak)")
        append("\(model)\(lineBreak)")

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"response_format\"\(lineBreak)\(lineBreak)")
        append("json\(lineBreak)")

        append("--\(boundary)\(lineBreak)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\(lineBreak)")
        append("Content-Type: audio/wav\(lineBreak)\(lineBreak)")
        body.append(try Data(contentsOf: url))
        append(lineBreak)
        append("--\(boundary)--\(lineBreak)")
        return body
    }
}
