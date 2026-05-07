import Foundation
import GRDB
import Observation

@Observable
final class CorrectionStore {
    private let db: DatabaseWriter

    // In-memory snapshot for UI — updated on every mutation
    private(set) var all: [CorrectionEntry] = []

    init(db: DatabaseWriter = LazyFlowDatabase.shared.writer) {
        self.db = db
        reload()
    }

    // MARK: - Core Query

    /// Returns corrections relevant to `transcript`, filtered by PhoneticMatcher,
    /// sorted by frequency descending, capped at 10.
    /// Includes per-app corrections for `bundleID` plus all global (nil) corrections.
    func relevantCorrections(for transcript: String, bundleID: String?) -> [CorrectionEntry] {
        let candidates = fetch(bundleID: bundleID)
        return candidates
            .filter { PhoneticMatcher.isRelevant(heard: $0.heard, to: transcript) }
            .sorted { $0.frequency > $1.frequency }
            .prefix(10)
            .map { $0 }
    }

    // MARK: - CRUD

    // Upserts: if an entry with the same heard+bundleIdentifier already exists, updates its
    // `correct` value and increments frequency rather than creating a duplicate row.
    func add(_ entry: CorrectionEntry) {
        guard !entry.heard.isEmpty, !entry.correct.isEmpty else { return }
        do {
            try db.write { db in
                let existing = try CorrectionEntry
                    .filter(Column("heard") == entry.heard)
                    .filter(entry.bundleIdentifier == nil
                        ? Column("bundleIdentifier") == nil
                        : Column("bundleIdentifier") == entry.bundleIdentifier)
                    .fetchOne(db)

                if var existing {
                    // Only update the correct spelling and timestamp — do NOT touch frequency.
                    // frequency is exclusively managed by incrementFrequency(for:), which is
                    // called when a correction is actually applied to a transcript.
                    existing.correct  = entry.correct
                    existing.lastUsed = Date()
                    try existing.update(db)
                } else {
                    try entry.insert(db)
                }
            }
            reload()
        } catch {
            print("[LazyFlow] CorrectionStore.add failed: \(error)")
        }
    }

    func delete(_ id: String) {
        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM corrections WHERE id = ?", arguments: [id])
            }
            reload()
        } catch {
            print("[LazyFlow] CorrectionStore.delete failed: \(error)")
        }
    }

    func incrementFrequency(for ids: [String]) {
        guard !ids.isEmpty else { return }
        do {
            try db.write { db in
                let now = Date().timeIntervalSince1970
                for id in ids {
                    try db.execute(
                        sql: "UPDATE corrections SET frequency = frequency + 1, lastUsed = ? WHERE id = ?",
                        arguments: [now, id]
                    )
                }
            }
        } catch {
            print("[LazyFlow] CorrectionStore.incrementFrequency failed: \(error)")
        }
    }

    // MARK: - Private

    private func fetch(bundleID: String?) -> [CorrectionEntry] {
        (try? db.read { db -> [CorrectionEntry] in
            if let bundleID {
                return try CorrectionEntry
                    .filter(Column("bundleIdentifier") == nil ||
                            Column("bundleIdentifier") == bundleID)
                    .order(Column("frequency").desc)
                    .fetchAll(db)
            } else {
                return try CorrectionEntry
                    .filter(Column("bundleIdentifier") == nil)
                    .order(Column("frequency").desc)
                    .fetchAll(db)
            }
        }) ?? []
    }

    func reload() {
        all = fetch(bundleID: nil) + ((try? db.read { db in
            try CorrectionEntry
                .filter(Column("bundleIdentifier") != nil)
                .order(Column("frequency").desc)
                .fetchAll(db)
        }) ?? [])
    }

    // All corrections visible to a given app (global + per-app). Used for STT vocabulary hint.
    func allCorrections(for bundleID: String?) -> [CorrectionEntry] {
        fetch(bundleID: bundleID)
    }

    // Corrections scoped to one app only (no globals). Used by ProfileEditorView.
    func corrections(for bundleID: String) -> [CorrectionEntry] {
        (try? db.read { db in
            try CorrectionEntry
                .filter(Column("bundleIdentifier") == bundleID)
                .order(Column("frequency").desc)
                .fetchAll(db)
        }) ?? []
    }
}
