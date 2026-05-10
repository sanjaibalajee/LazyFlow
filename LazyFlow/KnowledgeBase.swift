import Foundation
import GRDB

// MARK: - Model

struct KnowledgeEntry: Codable, Identifiable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "knowledgeBase"

    var id: String
    var fieldType: String
    var value: String
    var label: String?
    var createdAt: Date

    init(fieldType: String, value: String, label: String? = nil) {
        id        = UUID().uuidString
        self.fieldType = fieldType
        self.value     = value
        self.label     = label
        createdAt = Date()
    }
}

// MARK: - Well-known fields

enum KBField: String, CaseIterable {
    case name, email, phone, company, jobTitle, location, bio, website

    var displayName: String {
        switch self {
        case .name:     "Full Name"
        case .email:    "Email"
        case .phone:    "Phone"
        case .company:  "Company"
        case .jobTitle: "Job Title"
        case .location: "Location"
        case .bio:      "Bio"
        case .website:  "Website"
        }
    }

    var icon: String {
        switch self {
        case .name:     "person.fill"
        case .email:    "envelope.fill"
        case .phone:    "phone.fill"
        case .company:  "building.2.fill"
        case .jobTitle: "briefcase.fill"
        case .location: "location.fill"
        case .bio:      "text.alignleft"
        case .website:  "globe"
        }
    }

    var placeholder: String {
        switch self {
        case .name:     "Your full name"
        case .email:    "you@example.com"
        case .phone:    "+1 (555) 000-0000"
        case .company:  "Company name"
        case .jobTitle: "Founder & CEO"
        case .location: "San Francisco, CA"
        case .bio:      "A short description about yourself"
        case .website:  "https://yoursite.com"
        }
    }
}

// MARK: - Store

@Observable
@MainActor
final class KnowledgeStore {
    static let shared = KnowledgeStore()

    private(set) var entries: [KnowledgeEntry] = []

    private init() { load() }

    func load() {
        do {
            entries = try LazyFlowDatabase.shared.writer.read { db in
                try KnowledgeEntry.fetchAll(db)
            }
        } catch {
            print("[KB] load failed: \(error)")
        }
    }

    func set(field: KBField, value: String) {
        set(fieldType: field.rawValue, value: value, label: field.displayName)
    }

    func set(fieldType: String, value: String, label: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            // All DB access stays inside the write closure — no MainActor crossing.
            try LazyFlowDatabase.shared.writer.write { db in
                if trimmed.isEmpty {
                    try db.execute(sql: "DELETE FROM knowledgeBase WHERE fieldType = ?",
                                   arguments: [fieldType])
                } else {
                    let existing = try KnowledgeEntry
                        .filter(Column("fieldType") == fieldType)
                        .fetchOne(db)
                    if var e = existing {
                        e.value = trimmed
                        try e.update(db)
                    } else {
                        try KnowledgeEntry(fieldType: fieldType, value: trimmed, label: label).insert(db)
                    }
                }
            }
            // Update in-memory state directly — avoids a full DB round-trip mid-typing
            if trimmed.isEmpty {
                entries.removeAll { $0.fieldType == fieldType }
            } else if let i = entries.firstIndex(where: { $0.fieldType == fieldType }) {
                entries[i].value = trimmed
            } else {
                entries.append(KnowledgeEntry(fieldType: fieldType, value: trimmed, label: label))
            }
        } catch {
            print("[KB] set failed: \(error)")
        }
    }

    func value(for field: KBField) -> String {
        entries.first { $0.fieldType == field.rawValue }?.value ?? ""
    }

    // Compact block injected into LLM system prompts.
    var contextBlock: String? {
        let lines = KBField.allCases.compactMap { field -> String? in
            let v = value(for: field)
            return v.isEmpty ? nil : "\(field.displayName): \(v)"
        }
        guard !lines.isEmpty else { return nil }
        return "User profile:\n" + lines.joined(separator: "\n")
    }
}
