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
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            print("[LazyFlow] Could not create database directory: \(error)")
        }

        let url = dir.appendingPathComponent("lazyflow.db")
        writer = Self.openWriter(at: url, fileManager: fm)

        // Migration failure is logged but non-fatal — existing rows remain accessible.
        do {
            try migrate()
        } catch {
            print("[LazyFlow] DB migration failed: \(error)")
        }
    }

    private static func openWriter(at url: URL, fileManager fm: FileManager) -> DatabaseWriter {
        do {
            return try DatabasePool(path: url.path)
        } catch {
            print("[LazyFlow] DB open failed (\(error)) — preserving it and starting fresh")
        }

        let backupDirectory = url.deletingLastPathComponent()
            .appendingPathComponent("Database Backups", isDirectory: true)
            .appendingPathComponent("lazyflow-\(UUID().uuidString)", isDirectory: true)

        do {
            try fm.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: url.path + suffix)
                guard fm.fileExists(atPath: source.path) else { continue }
                try fm.moveItem(
                    at: source,
                    to: backupDirectory.appendingPathComponent(source.lastPathComponent)
                )
            }
            print("[LazyFlow] Preserved unreadable database at \(backupDirectory.path)")
        } catch {
            print("[LazyFlow] Could not preserve unreadable database: \(error)")
        }

        do {
            return try DatabasePool(path: url.path)
        } catch {
            print("[LazyFlow] Fresh database open failed (\(error)) — using volatile storage")
        }

        if let memoryQueue = try? DatabaseQueue() {
            return memoryQueue
        }

        // SQLite could not even allocate an in-memory database; continuing would leave every
        // store unusable. Keep the failure explicit and diagnostic instead of force-unwrapping.
        fatalError("LazyFlow could not initialize persistent or in-memory storage")
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
