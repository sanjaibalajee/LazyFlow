import Foundation
import GRDB
import Observation

@Observable
final class TranscriptStore {
    private let db: DatabaseWriter

    // Published array for SwiftUI — mirrors the DB, newest first, capped at 200
    private(set) var entries: [TranscriptEntry] = []

    init(db: DatabaseWriter = LazyFlowDatabase.shared.writer) {
        self.db = db
        entries = load()
    }

    // MARK: - Write

    func insert(_ entry: TranscriptEntry) {
        do {
            try db.write { db in
                try entry.insert(db)
                // Prune rows beyond the 200 most recent atomically in the same transaction
                // so the DB doesn't grow unbounded while the in-memory array stays capped.
                try db.execute(sql: """
                    DELETE FROM transcripts
                    WHERE id IN (
                        SELECT id FROM transcripts
                        ORDER BY date DESC
                        LIMIT -1 OFFSET 200
                    )
                    """)
            }
            entries.insert(entry, at: 0)
            if entries.count > 200 { entries = Array(entries.prefix(200)) }
        } catch {
            print("[LazyFlow] TranscriptStore.insert failed: \(error)")
        }
    }

    func update(_ entry: TranscriptEntry) {
        do {
            try db.write { db in try entry.update(db) }
            if let idx = entries.firstIndex(where: { $0.id == entry.id }) {
                entries[idx] = entry
            }
        } catch {
            print("[LazyFlow] TranscriptStore.update failed: \(error)")
        }
    }

    func delete(_ id: String) {
        do {
            try db.write { db in
                try db.execute(sql: "DELETE FROM transcripts WHERE id = ?", arguments: [id])
            }
            entries.removeAll { $0.id == id }
        } catch {
            print("[LazyFlow] TranscriptStore.delete failed: \(error)")
        }
    }

    // MARK: - Private

    private func load() -> [TranscriptEntry] {
        (try? db.read { db in
            try TranscriptEntry
                .order(Column("date").desc)
                .limit(200)
                .fetchAll(db)
        }) ?? []
    }
}
