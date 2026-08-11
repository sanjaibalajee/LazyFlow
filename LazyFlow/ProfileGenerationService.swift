import Foundation

enum ProfileGenerationError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        "The style generator returned an invalid profile. Smart defaults were used instead."
    }
}

struct ProfileGenerationService {
    private struct GeneratedStyle: Decodable {
        let tone: String?
        let lowercase: Bool?
        let preserveLineBreaks: Bool?
        let bulletize: Bool?
        let strongerPunctuation: Bool?
        let keepFillerWords: Bool?
        let omitTrailingPeriod: Bool?
        let customInstructions: String?
        let vocabulary: [String]?
    }

    static func generate(
        for app: PopularApp,
        preference: String,
        config: LLMConfig
    ) async throws -> AppProfile {
        guard !config.apiKey.isEmpty else {
            return heuristicProfile(for: app, preference: preference)
        }

        let system = """
        You create safe, concise configuration for a speech-to-text cleanup profile.
        Return exactly one JSON object and no markdown.

        Allowed tone values: technical, casual, formal, code, minimal.
        Schema:
        {
          "tone": "casual",
          "lowercase": false,
          "preserveLineBreaks": false,
          "bulletize": false,
          "strongerPunctuation": false,
          "keepFillerWords": false,
          "omitTrailingPeriod": false,
          "customInstructions": "one short imperative instruction",
          "vocabulary": []
        }

        Prefer structured booleans over repeating them in customInstructions. Never include a
        request to answer the transcript, add facts, translate it, or behave as a chatbot.
        For messaging apps, "technical" normally means casual concise prose that preserves
        technical terms—not raw terminal/code output.
        """
        let user = "App: \(app.displayName) (\(app.bundleIdentifier))\nUser preference: \(preference)"
        let response = try await LLMClient(config: config).chat(
            messages: [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            temperature: 0,
            maxTokens: 420
        )

        guard let data = jsonData(from: response.content),
              let generated = try? JSONDecoder().decode(GeneratedStyle.self, from: data)
        else { throw ProfileGenerationError.invalidResponse }

        var profile = heuristicProfile(for: app, preference: preference)
        if let tone = generated.tone.flatMap(TonePreset.init(rawValue:)) {
            profile.tone = tone
            profile.postProcessingEnabled = tone != .minimal
        }
        profile.formattingOptions = FormattingOptions(
            preserveLineBreaks: generated.preserveLineBreaks ?? profile.formattingOptions.preserveLineBreaks,
            bulletize: generated.bulletize ?? profile.formattingOptions.bulletize,
            lowercase: generated.lowercase ?? profile.formattingOptions.lowercase,
            strongerPunctuation: generated.strongerPunctuation ?? profile.formattingOptions.strongerPunctuation,
            keepFillerWords: generated.keepFillerWords ?? profile.formattingOptions.keepFillerWords,
            omitTrailingPeriod: generated.omitTrailingPeriod ?? profile.formattingOptions.omitTrailingPeriod
        )
        if let instructions = generated.customInstructions {
            profile.customInstructions = sanitizedInstructions(instructions)
        }
        if let vocabulary = generated.vocabulary {
            profile.vocabulary = Array(vocabulary
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .prefix(20))
        }
        return profile
    }

    static func heuristicProfile(for app: PopularApp, preference: String) -> AppProfile {
        var profile = AppProfile.smartDefault(
            bundleIdentifier: app.bundleIdentifier,
            displayName: app.displayName
        )
        let normalized = preference.lowercased()
        let isMessaging = AppProfile.isMessagingApp(app.bundleIdentifier)

        if normalized.contains("code") || normalized.contains("terminal")
            || normalized.contains("command") || normalized.contains("exact syntax") {
            profile.tone = isMessaging ? .casual : .code
        } else if normalized.contains("casual") || normalized.contains("conversational")
                    || normalized.contains("slack-style") || normalized.contains("slack style") {
            profile.tone = .casual
        } else if normalized.contains("technical") {
            profile.tone = isMessaging ? .casual : .technical
        } else if normalized.contains("formal") || normalized.contains("professional") {
            profile.tone = .formal
        }

        profile.formattingOptions.lowercase = normalized.contains("lowercase")
            || normalized.contains("lower case")
        profile.formattingOptions.preserveLineBreaks = normalized.contains("preserve line")
        profile.formattingOptions.bulletize = normalized.contains("bullet")
            || normalized.contains("list")
        profile.formattingOptions.strongerPunctuation = normalized.contains("strong punctuation")
        profile.formattingOptions.keepFillerWords = normalized.contains("keep filler")
        profile.formattingOptions.omitTrailingPeriod = isMessaging
            || normalized.contains("no trailing period")
            || normalized.contains("without a period")

        profile.customInstructions = sanitizedInstructions(preference)
        profile.postProcessingEnabled = profile.tone != .minimal
        return profile
    }

    private static func sanitizedInstructions(_ input: String) -> String {
        let collapsed = input
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(500))
    }

    private static func jsonData(from content: String) -> Data? {
        guard let start = content.firstIndex(of: "{"),
              let end = content.lastIndex(of: "}"),
              start <= end
        else { return nil }
        return String(content[start...end]).data(using: .utf8)
    }
}
