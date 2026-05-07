import Foundation
import GRDB

// Shared database writer — all reads/writes go through here.
// DatabaseQueue serialises access so no concurrent-write crashes.

final class LazyFlowDatabase {
    static let shared = LazyFlowDatabase()

    let writer: DatabaseWriter

    private init() {
        let fm  = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("LazyFlow", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        let url = dir.appendingPathComponent("lazyflow.db")

        // Open the pool; if it fails (corrupt file, permission error) rename it aside
        // and start fresh rather than crashing.
        do {
            writer = try DatabasePool(path: url.path)
        } catch {
            print("[LazyFlow] DB open failed (\(error)) — moving aside and starting fresh")
            let aside = url.deletingPathExtension().appendingPathExtension("db.bak")
            try? fm.moveItem(at: url, to: aside)
            writer = try! DatabasePool(path: url.path) // fresh file, guaranteed to succeed
        }

        // Migration failure is logged but non-fatal — existing rows remain accessible.
        do {
            try migrate()
        } catch {
            print("[LazyFlow] DB migration failed: \(error)")
        }
    }

    // MARK: - Migrations (additive only — never drop columns/tables)

    private func migrate() throws {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "transcripts", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("text",              .text).notNull()
                t.column("date",              .double).notNull()
                t.column("appName",           .text)
                t.column("bundleIdentifier",  .text)
            }

            try db.create(table: "corrections", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("heard",             .text).notNull()
                t.column("correct",           .text).notNull()
                t.column("bundleIdentifier",  .text)
                t.column("frequency",         .integer).notNull().defaults(to: 0)
                t.column("lastUsed",          .double)
                t.column("createdAt",         .double).notNull()
            }

            // Schema ready for Phase 4 smart fill — populated later
            try db.create(table: "knowledgeBase", ifNotExists: true) { t in
                t.primaryKey("id", .text)
                t.column("fieldType",   .text).notNull()
                t.column("value",       .text).notNull()
                t.column("label",       .text)
                t.column("createdAt",   .double).notNull()
            }
        }

        try m.migrate(writer)
    }
}
