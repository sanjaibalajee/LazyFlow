import Foundation
import Metal
import HuggingFace   // required by #huggingFaceLoadModelContainer macro expansion
import Tokenizers    // required by #huggingFaceLoadModelContainer macro expansion
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import MLX

// MARK: - Service

actor LocalLLMService {

    private var container: ModelContainer?
    private(set) var loadedModel: LocalLLMModel?

    var isReady: Bool { container != nil }

    // MARK: - Load

    func load(_ model: LocalLLMModel,
              onProgress: @escaping @Sendable (Double, String) -> Void) async throws {
        if loadedModel == model, container != nil { return }
        container   = nil
        loadedModel = nil

        onProgress(0.03, "Preparing…")
        let config = ModelConfiguration(id: model.rawValue)

        let loaded = try await #huggingFaceLoadModelContainer(
            configuration: config,
            progressHandler: { progress in
                let frac = min(max(progress.fractionCompleted * 0.95, 0.03), 0.95)
                let done  = progress.completedUnitCount
                let total = progress.totalUnitCount
                let status: String
                if total > 10_000_000 {
                    let doneMB  = done  / 1_048_576
                    let totalMB = total / 1_048_576
                    if let bps = progress.userInfo[.throughputKey] as? Double, bps > 0 {
                        let mbps = bps / 1_048_576
                        status = "\(doneMB) / \(totalMB) MB · \(String(format: "%.1f", mbps)) MB/s"
                    } else {
                        status = "\(doneMB) / \(totalMB) MB"
                    }
                } else {
                    status = "Downloading… \(Int(progress.fractionCompleted * 100))%"
                }
                onProgress(frac, status)
            }
        )

        container   = loaded
        loadedModel = model

        let memGB    = GPU.deviceInfo().memorySize / 1_073_741_824
        let devName  = MTLCreateSystemDefaultDevice()?.name ?? "unknown"
        let activeMB = Memory.snapshot().activeMemory / 1_048_576
        print("[LazyFlow] ✅ MLX device: \(devName) · \(memGB) GB unified memory")
        print("[LazyFlow] ✅ MLX model resident: \(activeMB) MB active in GPU memory pool")

        onProgress(1.0, "Ready")
    }

    // MARK: - Post-process

    func process(rawTranscript: String,
                 profile: AppProfile,
                 corrections: [CorrectionEntry] = [],
                 kbContext: String? = nil,
                 focusContext: FocusContext? = nil) async throws -> String {
        guard let container else { throw LocalLLMError.notLoaded }
        guard let (setup, style) = profile.resolvedPromptComponents else { return rawTranscript }

        var systemPrompt = setup
        if !corrections.isEmpty {
            let pairs = corrections.map { "- \"\($0.heard)\" → \"\($0.correct)\"" }.joined(separator: "\n")
            systemPrompt += "\n\nSpeech correction pairs (correct before applying formatting):\n\(pairs)"
        }

        var styleBlock = style

        if let focus = focusContext {
            styleBlock += """


            SMART FILL — STRICT RULES (override everything above):
            You are populating \(focus.description).
            Output ONLY the exact text to insert into that field. Nothing else.
            - No field-name prefix (never "First Name: value" — just "value")
            - No punctuation added around the value
            - No explanation, preamble, or trailing text
            - "First Name" / "given name" / "forename" → first name only
            - "Last Name" / "surname" / "family name" → last name only
            - "Full Name" / "name" → complete name
            - "Email" / "email address" → email only
            - "Phone" / "mobile" / "tel" → phone number only
            - "Company" / "organisation" → company name only
            - "Job Title" / "title" / "role" → job title only
            - "Location" / "city" / "address" → location only
            - "Website" / "URL" → URL only
            \(kbContext.map { "\n" + $0 } ?? "")
            Output the field value only. One line. No label.
            """
        } else if let kb = kbContext {
            styleBlock += "\n\nUser profile (use when relevant to the transcript):\n\(kb)"
        }
        systemPrompt += "\n\n" + styleBlock

        // /no_think suppresses Qwen3's chain-of-thought. Thinking adds no quality for
        // deterministic formatting tasks and burned all 4096 tokens without finishing.
        let userInput = UserInput(chat: [
            .system(systemPrompt),
            .user("/no_think\n\nInput:\n\n\(rawTranscript)")
        ])

        let params = GenerateParameters(
            maxTokens: 1024,
            temperature: 0,
            topP: 1.0
        )

        let lmInput = try await container.prepare(input: userInput)
        let stream  = try await container.generate(input: lmInput, parameters: params)

        let genStart = Date()
        var result = ""
        var chunkCount = 0
        for await generation in stream {
            if case .chunk(let text) = generation {
                result += text
                chunkCount += 1
            }
        }
        let genSec = Date().timeIntervalSince(genStart)
        let tokPerSec = genSec > 0 ? Double(chunkCount) / genSec : 0
        let afterMB = Memory.snapshot().activeMemory / 1_048_576
        print("[LazyFlow] 🧠 MLX inference: ~\(chunkCount) tokens in \(String(format: "%.2f", genSec))s = \(String(format: "%.1f", tokPerSec)) tok/s · \(afterMB) MB active")
        print("[LazyFlow] 🧠 raw output (\(result.count) chars): \(result.prefix(300))")

        // Strip any residual <think>…</think> block (unclosed tags stripped greedily).
        var cleaned = result
        if let start = cleaned.range(of: "<think>") {
            if let end = cleaned.range(of: "</think>") {
                // closed block — remove it plus any trailing whitespace
                let removeEnd = cleaned.index(end.upperBound,
                                              offsetBy: cleaned[end.upperBound...].prefix(while: \.isWhitespace).count)
                cleaned.removeSubrange(start.lowerBound..<removeEnd)
            } else {
                // unclosed block — model hit token limit inside <think>; discard everything
                cleaned = String(cleaned[..<start.lowerBound])
                print("[LazyFlow] ⚠️ local LLM hit token limit inside <think> block — output discarded, returning raw transcript")
            }
        }

        let final = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[LazyFlow] 🧠 local LLM cleaned output (\(final.count) chars): \(final.prefix(200))")

        // If nothing survived stripping, fall back to the raw transcript so the
        // user at least gets their words rather than an empty paste.
        return final.isEmpty ? rawTranscript : final
    }

    // MARK: - Unload

    func unload(_ model: LocalLLMModel) {
        guard loadedModel == model else { return }
        container   = nil
        loadedModel = nil
    }

    // MARK: - Disk helpers

    static func isDownloaded(_ model: LocalLLMModel) -> Bool {
        let cacheKey = model.rawValue.replacingOccurrences(of: "/", with: "--")
        let snapshots = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(cacheKey)/snapshots")
        // snapshots/ is only created after a complete successful download
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: snapshots.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func delete(_ model: LocalLLMModel) {
        let cacheKey = model.rawValue.replacingOccurrences(of: "/", with: "--")
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(cacheKey)")
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: - Error

enum LocalLLMError: LocalizedError {
    case notLoaded
    var errorDescription: String? {
        "Local LLM not ready. Select and download a model in Settings → Post-processing."
    }
}
