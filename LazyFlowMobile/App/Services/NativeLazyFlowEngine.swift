import AVFoundation
import Foundation
import FoundationModels
import Speech

enum NativeLazyFlowError: LocalizedError {
    case unsupportedLocale
    case emptyTranscript

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale:
            "On-device transcription is not available for this language."
        case .emptyTranscript:
            "I couldn't hear any words. Try speaking a little closer to the microphone."
        }
    }
}

struct NativeLazyFlowEngine {
    func transcribeAndRefine(
        recordingAt url: URL,
        tone: MobileTone,
        locale: Locale = .autoupdatingCurrent
    ) async throws -> String {
        let transcript = try await transcribe(recordingAt: url, locale: locale)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcript.isEmpty else { throw NativeLazyFlowError.emptyTranscript }
        guard tone != .verbatim else { return transcript }
        return await refine(transcript, tone: tone)
    }

    private func transcribe(recordingAt url: URL, locale: Locale) async throws -> String {
        guard let supportedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw NativeLazyFlowError.unsupportedLocale
        }

        let transcriber = SpeechTranscriber(
            locale: supportedLocale,
            preset: .transcription
        )
        if let installation = try await AssetInventory.assetInstallationRequest(
            supporting: [transcriber]
        ) {
            try await installation.downloadAndInstall()
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: url)
        async let transcription = transcriber.results.reduce(into: "") { text, result in
            text += String(result.text.characters)
        }

        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }
        return try await transcription
    }

    private func refine(_ transcript: String, tone: MobileTone) async -> String {
        let fallback = deterministicCleanup(transcript)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return fallback }

        let session = LanguageModelSession(
            model: model,
            instructions: tone.editingInstructions
        )
        do {
            let response = try await session.respond(to: transcript)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return output.isEmpty ? fallback : output
        } catch {
            return fallback
        }
    }

    private func deterministicCleanup(_ transcript: String) -> String {
        let words = transcript.split(whereSeparator: \.isWhitespace)
        guard var cleaned = words.joined(separator: " ").nilIfEmpty else { return transcript }
        if let first = cleaned.first, first.isLetter {
            cleaned.replaceSubrange(cleaned.startIndex...cleaned.startIndex, with: String(first).uppercased())
        }
        return cleaned
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
