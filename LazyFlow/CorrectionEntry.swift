import Foundation
import GRDB

// A correction pair: what Whisper heard → what it should be.
// nil bundleIdentifier = global (applies to all apps).
// Non-nil bundleIdentifier = per-app override.

struct CorrectionEntry: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "corrections"

    var id:               String = UUID().uuidString
    var heard:            String   // "san chai balaji"
    var correct:          String   // "Sanjaibalajee"
    var bundleIdentifier: String?  // nil = global
    var frequency:        Int    = 0
    var lastUsed:         Date?
    var createdAt:        Date   = Date()

    init(heard: String, correct: String, bundleIdentifier: String? = nil) {
        self.heard   = Self.normalizedPhrase(heard)
        self.correct = Self.normalizedPhrase(correct)
        self.bundleIdentifier = bundleIdentifier
    }

    nonisolated static func normalizedPhrase(_ value: String) -> String {
        let punctuation = CharacterSet(charactersIn: ".,;:!?\"'")
        return value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: punctuation)
    }
}
