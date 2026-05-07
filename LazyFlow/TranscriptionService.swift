import Foundation

enum TranscriptionError: LocalizedError {
    case missingAPIKey
    case httpError(Int, String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:         return "No API key set. Add your Groq key in Settings."
        case .httpError(let c, let m): return "Transcription failed (\(c)): \(m)"
        case .decodingFailed:        return "Could not parse transcription response."
        }
    }
}

struct TranscriptionService {
    private let baseURL: String
    private let apiKey: String
    private let model: String

    init(apiKey: String, baseURL: String = "https://api.groq.com/openai/v1", model: String = "whisper-large-v3") {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    // vocabularyHint: comma-separated terms passed as Whisper's `prompt` field to bias
    // transcription toward correct spellings of names, jargon, and proper nouns.
    func transcribe(audioURL: URL, vocabularyHint: String = "") async throws -> String {
        guard !apiKey.isEmpty else { throw TranscriptionError.missingAPIKey }

        let endpoint = URL(string: "\(baseURL)/audio/transcriptions")!
        var request = URLRequest(url: endpoint, timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = try buildBody(audioURL: audioURL, boundary: boundary, vocabularyHint: vocabularyHint)

        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        print("[LazyFlow] 📡 HTTP \(statusCode)")

        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            let rawBody = String(data: data, encoding: .utf8) ?? "unknown"
#if DEBUG
            print("[LazyFlow] 📡 STT error body: \(rawBody)")
#endif
            throw TranscriptionError.httpError(http.statusCode, "Transcription service returned \(http.statusCode) — check your API key or try again.")
        }

        struct Response: Decodable { let text: String }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw TranscriptionError.decodingFailed
        }
        return decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildBody(audioURL: URL, boundary: String, vocabularyHint: String) throws -> Data {
        var body = Data()
        let audioData = try Data(contentsOf: audioURL)
        let crlf = "\r\n"

        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        // model field
        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"model\"\(crlf)\(crlf)")
        append("\(model)\(crlf)")

        // response_format field
        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"response_format\"\(crlf)\(crlf)")
        append("json\(crlf)")

        // prompt field — biases Whisper toward correct spellings of names and terms
        if !vocabularyHint.isEmpty {
            append("--\(boundary)\(crlf)")
            append("Content-Disposition: form-data; name=\"prompt\"\(crlf)\(crlf)")
            append("\(vocabularyHint)\(crlf)")
        }

        // audio file
        append("--\(boundary)\(crlf)")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\(crlf)")
        append("Content-Type: audio/wav\(crlf)\(crlf)")
        body.append(audioData)
        append(crlf)

        append("--\(boundary)--\(crlf)")
        return body
    }
}
