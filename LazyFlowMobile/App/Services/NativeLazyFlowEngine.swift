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
    private let groq = GroqService()

    func transcribeAndRefine(
        recordingAt url: URL,
        tone: MobileTone,
        configuration: ProcessingConfiguration,
        locale: Locale = .autoupdatingCurrent
    ) async throws -> ProcessingResult {
        let transcript: String
        let transcriptionLabel: String
        switch configuration.transcriptionProvider {
        case .apple:
            transcript = try await transcribeOnDevice(recordingAt: url, locale: locale)
            transcriptionLabel = "Apple SpeechAnalyzer"
        case .groq:
            transcript = try await groq.transcribe(
                recordingAt: url,
                apiKey: configuration.groqAPIKey,
                model: configuration.speechModel
            )
            transcriptionLabel = configuration.speechModel.title
        }

        let trimmedTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTranscript.isEmpty else { throw NativeLazyFlowError.emptyTranscript }

        if tone == .verbatim {
            return ProcessingResult(
                transcript: trimmedTranscript,
                finalText: trimmedTranscript,
                transcriptionLabel: transcriptionLabel,
                rewriteLabel: "None · Verbatim"
            )
        }

        let finalText: String
        let rewriteLabel: String
        switch configuration.rewriteProvider {
        case .apple:
            (finalText, rewriteLabel) = await refineOnDevice(trimmedTranscript, tone: tone)
        case .groq:
            finalText = try await groq.refine(
                trimmedTranscript,
                tone: tone,
                apiKey: configuration.groqAPIKey,
                model: configuration.rewriteModel
            )
            rewriteLabel = configuration.rewriteModel.title
        }

        return ProcessingResult(
            transcript: trimmedTranscript,
            finalText: finalText,
            transcriptionLabel: transcriptionLabel,
            rewriteLabel: rewriteLabel
        )
    }

    private func transcribeOnDevice(recordingAt url: URL, locale: Locale) async throws -> String {
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

    private func refineOnDevice(
        _ transcript: String,
        tone: MobileTone
    ) async -> (text: String, label: String) {
        let fallback = deterministicCleanup(transcript)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return (fallback, "Local cleanup")
        }

        let session = LanguageModelSession(
            model: model,
            instructions: tone.editingInstructions
        )
        do {
            let response = try await session.respond(to: transcript)
            let output = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return (output.isEmpty ? fallback : output, "Apple Foundation Models")
        } catch {
            return (fallback, "Local cleanup")
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
