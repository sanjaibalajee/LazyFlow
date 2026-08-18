import Foundation

@MainActor
final class ProcessingSettings: ObservableObject {
    @Published var transcriptionProvider: TranscriptionProvider {
        didSet { defaults.set(transcriptionProvider.rawValue, forKey: Key.transcriptionProvider) }
    }
    @Published var rewriteProvider: RewriteProvider {
        didSet { defaults.set(rewriteProvider.rawValue, forKey: Key.rewriteProvider) }
    }
    @Published var speechModel: GroqSpeechModel {
        didSet { defaults.set(speechModel.rawValue, forKey: Key.speechModel) }
    }
    @Published var rewriteModel: GroqRewriteModel {
        didSet { defaults.set(rewriteModel.rawValue, forKey: Key.rewriteModel) }
    }
    @Published private(set) var hasGroqKey: Bool
    @Published private(set) var keyEnding = ""

    private enum Key {
        static let transcriptionProvider = "mobile.processing.transcriptionProvider"
        static let rewriteProvider = "mobile.processing.rewriteProvider"
        static let speechModel = "mobile.processing.speechModel"
        static let rewriteModel = "mobile.processing.rewriteModel"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        transcriptionProvider = TranscriptionProvider(
            rawValue: defaults.string(forKey: Key.transcriptionProvider) ?? ""
        ) ?? .apple
        rewriteProvider = RewriteProvider(
            rawValue: defaults.string(forKey: Key.rewriteProvider) ?? ""
        ) ?? .apple
        speechModel = GroqSpeechModel(
            rawValue: defaults.string(forKey: Key.speechModel) ?? ""
        ) ?? .turbo
        rewriteModel = GroqRewriteModel(
            rawValue: defaults.string(forKey: Key.rewriteModel) ?? ""
        ) ?? .fast

        let storedKey = MobileKeychain.load(for: MobileKeychain.groqKey) ?? ""
        hasGroqKey = !storedKey.isEmpty
        keyEnding = String(storedKey.suffix(4))
    }

    var needsGroqKey: Bool {
        transcriptionProvider == .groq || rewriteProvider == .groq
    }

    func configuration() -> ProcessingConfiguration {
        ProcessingConfiguration(
            transcriptionProvider: transcriptionProvider,
            rewriteProvider: rewriteProvider,
            speechModel: speechModel,
            rewriteModel: rewriteModel,
            groqAPIKey: MobileKeychain.load(for: MobileKeychain.groqKey) ?? ""
        )
    }

    func saveGroqKey(_ rawValue: String) throws {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        try MobileKeychain.save(value, for: MobileKeychain.groqKey)
        hasGroqKey = true
        keyEnding = String(value.suffix(4))
    }

    func removeGroqKey() throws {
        try MobileKeychain.delete(for: MobileKeychain.groqKey)
        hasGroqKey = false
        keyEnding = ""
        if transcriptionProvider == .groq { transcriptionProvider = .apple }
        if rewriteProvider == .groq { rewriteProvider = .apple }
    }
}
