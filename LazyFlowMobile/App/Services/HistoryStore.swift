import Foundation

struct MobileHistoryEntry: Identifiable, Codable, Equatable, Sendable {
    var id: UUID
    var createdAt: Date
    var transcript: String
    var finalText: String
    var tone: MobileTone
    var transcriptionLabel: String
    var rewriteLabel: String
}

@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var entries: [MobileHistoryEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL? = nil) {
        let directory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("LazyFlowMobile", isDirectory: true)
        self.fileURL = fileURL ?? directory.appendingPathComponent("history.json")
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
        load()
    }

    func add(_ result: ProcessingResult, tone: MobileTone) {
        entries.insert(
            MobileHistoryEntry(
                id: UUID(),
                createdAt: Date(),
                transcript: result.transcript,
                finalText: result.finalText,
                tone: tone,
                transcriptionLabel: result.transcriptionLabel,
                rewriteLabel: result.rewriteLabel
            ),
            at: 0
        )
        persist()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets.sorted(by: >) {
            entries.remove(at: index)
        }
        persist()
    }

    func delete(_ entry: MobileHistoryEntry) {
        entries.removeAll { $0.id == entry.id }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? decoder.decode([MobileHistoryEntry].self, from: data) else {
            return
        }
        entries = decoded.sorted { $0.createdAt > $1.createdAt }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try encoder.encode(entries)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            assertionFailure("Unable to save LazyFlow history: \(error)")
        }
    }
}
