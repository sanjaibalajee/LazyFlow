import Foundation

enum TranscriptionError: LocalizedError {
    case missingAPIKey(String)
    case httpError(Int, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            return "No \(provider) API key set. Add it in Settings."
        case .httpError(let code, let message):
            return "Transcription failed (\(code)): \(message)"
        case .decodingFailed:
            return "Could not parse transcription response."
        }
    }
}

struct TranscriptionService {
    private let config: TranscriptionConfig

    init(config: TranscriptionConfig) {
        self.config = config
    }

    func transcribe(audioURL: URL, vocabularyTerms: [String] = []) async throws -> String {
        guard !config.apiKey.isEmpty else {
            throw TranscriptionError.missingAPIKey(config.provider.displayName)
        }

        let request = try makeRequest(audioURL: audioURL, vocabularyTerms: vocabularyTerms)
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
#if DEBUG
        print("[LazyFlow] 📡 \(config.provider.displayName) HTTP \(statusCode)")
#endif

        guard (200..<300).contains(statusCode) else {
#if DEBUG
            let rawBody = String(data: data, encoding: .utf8) ?? "unknown"
            print("[LazyFlow] 📡 STT error body: \(rawBody)")
#endif
            throw TranscriptionError.httpError(
                statusCode,
                "\(config.provider.displayName) returned \(statusCode) — check your API key or try again."
            )
        }

        struct Response: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TranscriptionError.decodingFailed
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func makeRequest(audioURL: URL, vocabularyTerms: [String] = []) throws -> URLRequest {
        var request = URLRequest(url: config.provider.endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"

        switch config.provider {
        case .groq, .openAI:
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        case .elevenLabs:
            request.setValue(config.apiKey, forHTTPHeaderField: "xi-api-key")
        }

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildBody(
            audioURL: audioURL,
            boundary: boundary,
            vocabularyTerms: vocabularyTerms
        )
        return request
    }

    private func buildBody(
        audioURL: URL,
        boundary: String,
        vocabularyTerms: [String]
    ) throws -> Data {
        var body = Data()
        let audioData = try Data(contentsOf: audioURL)
        let crlf = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        func appendField(name: String, value: String) {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"\(name)\"\(crlf)\(crlf)")
            append("\(value)\(crlf)")
        }

        switch config.provider {
        case .groq, .openAI:
            appendField(name: "model", value: config.model)
            appendField(name: "response_format", value: "json")

            let prompt = Self.prompt(from: vocabularyTerms)
            if !prompt.isEmpty {
                appendField(name: "prompt", value: prompt)
            }
        case .elevenLabs:
            appendField(name: "model_id", value: config.model)
            appendField(name: "tag_audio_events", value: "false")
            appendField(name: "timestamps_granularity", value: "none")
            for term in Self.elevenLabsKeyterms(from: vocabularyTerms) {
                appendField(name: "keyterms", value: term)
            }
        }

        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(crlf)")
        append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        append(crlf)
        append("--\(boundary)--\(crlf)")
        return body
    }

    private static func prompt(from terms: [String]) -> String {
        let cleaned = cleanedTerms(terms)
        guard !cleaned.isEmpty else { return "" }
        return "The following terms may appear in this transcript: \(cleaned.joined(separator: ", "))."
    }

    private static func elevenLabsKeyterms(from terms: [String]) -> [String] {
        let unsupported = CharacterSet(charactersIn: "<>{}[]\\")
        let supported = cleanedTerms(terms).filter { term in
            term.count < 50
                && term.split(whereSeparator: \.isWhitespace).count <= 5
                && term.rangeOfCharacter(from: unsupported) == nil
        }
        return Array(supported.prefix(1_000))
    }

    private static func cleanedTerms(_ terms: [String]) -> [String] {
        var seen = Set<String>()
        return terms.compactMap { term in
            let cleaned = term
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, seen.insert(cleaned.lowercased()).inserted else { return nil }
            return cleaned
        }
    }
}
