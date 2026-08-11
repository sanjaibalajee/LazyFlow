import Foundation
import Observation

struct VoiceSnippet: Codable, Identifiable, Equatable {
    let id: String
    var trigger: String
    var expansion: String
    let createdAt: Date

    init(id: String = UUID().uuidString, trigger: String, expansion: String, createdAt: Date = Date()) {
        self.id = id
        self.trigger = trigger
        self.expansion = expansion
        self.createdAt = createdAt
    }
}

@Observable
final class SnippetStore {
    private(set) var snippets: [VoiceSnippet] = []
    private let storageKey = "lf_voice_snippets"

    init() { load() }

    func upsert(_ snippet: VoiceSnippet) {
        if let index = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[index] = snippet
        } else {
            snippets.append(snippet)
        }
        snippets.sort { $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending }
        save()
    }

    func delete(_ id: String) {
        snippets.removeAll { $0.id == id }
        save()
    }

    /// Expands triggers only after cleanup so saved content keeps its exact casing and formatting.
    /// Longer triggers win, preventing a short trigger from consuming part of a longer one.
    func expand(in text: String) -> String {
        var result = text
        for snippet in snippets.sorted(by: { $0.trigger.count > $1.trigger.count }) {
            let trigger = snippet.trigger.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trigger.isEmpty else { continue }
            let escaped = NSRegularExpression.escapedPattern(for: trigger)
            guard let regex = try? NSRegularExpression(
                pattern: "(?i)(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
            ) else { continue }
            result = regex.stringByReplacingMatches(
                in: result,
                range: NSRange(result.startIndex..., in: result),
                withTemplate: NSRegularExpression.escapedTemplate(for: snippet.expansion)
            )
        }
        return result
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([VoiceSnippet].self, from: data)
        else { return }
        snippets = decoded.sorted {
            $0.trigger.localizedCaseInsensitiveCompare($1.trigger) == .orderedAscending
        }
    }
}
