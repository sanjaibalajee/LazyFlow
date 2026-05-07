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
        // Strip surrounding whitespace and sentence-ending punctuation so "rishin,"
        // and "rishin" store identically. The regex matcher uses word boundaries, so
        // the surrounding punctuation in text is preserved during replacement.
        let punct = CharacterSet(charactersIn: ".,;:!?\"'")
        self.heard   = heard.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: punct)
        self.correct = correct.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: punct)
        self.bundleIdentifier = bundleIdentifier
    }
}
