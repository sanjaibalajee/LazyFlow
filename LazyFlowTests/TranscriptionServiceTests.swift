import XCTest
@testable import LazyFlow

final class TranscriptionServiceTests: XCTestCase {
    func testGroqRequestKeepsWhisperCompatibility() throws {
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = TranscriptionService(config: TranscriptionConfig(
            provider: .groq,
            apiKey: "gsk-test",
            model: "whisper-large-v3-turbo"
        ))
        let request = try service.makeRequest(audioURL: audioURL)
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertEqual(request.url?.absoluteString, "https://api.groq.com/openai/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer gsk-test")
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\nwhisper-large-v3-turbo"))
    }

    func testOpenAIRequestUsesTranscriptionEndpointAndPrompt() throws {
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = TranscriptionService(config: TranscriptionConfig(
            provider: .openAI,
            apiKey: "sk-test",
            model: "gpt-transcribe"
        ))
        let request = try service.makeRequest(
            audioURL: audioURL,
            vocabularyTerms: ["LazyFlow", "SwiftUI"]
        )
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertTrue(body.contains("name=\"model\"\r\n\r\ngpt-transcribe"))
        XCTAssertTrue(body.contains("name=\"prompt\""))
        XCTAssertTrue(body.contains("LazyFlow, SwiftUI"))
    }

    func testElevenLabsRequestUsesScribeFieldsAndKeyterms() throws {
        let audioURL = try makeAudioFixture()
        defer { try? FileManager.default.removeItem(at: audioURL) }

        let service = TranscriptionService(config: TranscriptionConfig(
            provider: .elevenLabs,
            apiKey: "eleven-test",
            model: "scribe_v2"
        ))
        let request = try service.makeRequest(
            audioURL: audioURL,
            vocabularyTerms: ["LazyFlow", "ignored term with too many words here"]
        )
        let body = String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self)

        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "eleven-test")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(body.contains("name=\"model_id\"\r\n\r\nscribe_v2"))
        XCTAssertTrue(body.contains("name=\"tag_audio_events\"\r\n\r\nfalse"))
        XCTAssertTrue(body.contains("name=\"keyterms\"\r\n\r\nLazyFlow"))
        XCTAssertFalse(body.contains("ignored term with too many words here"))
    }

    private func makeAudioFixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("lazyflow-transcription-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46]).write(to: url)
        return url
    }
}
