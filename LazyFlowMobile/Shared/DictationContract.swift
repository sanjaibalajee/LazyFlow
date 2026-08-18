import Foundation

enum DictationPhase: String, Codable, Sendable {
    case off
    case preparing
    case ready
    case recording
    case processing
    case resultReady
    case failed
}

enum DictationCommand: String, Codable, Sendable {
    case none
    case beginSession
    case start
    case stop
    case cancel
    case endSession
}

struct DictationSnapshot: Equatable, Sendable {
    var phase: DictationPhase
    var tone: MobileTone
    var command: DictationCommand
    var commandID: String
    var result: String
    var resultID: String
    var errorMessage: String
    var audioLevel: Double
    var sessionExpiresAt: Date?

    var isSessionActive: Bool {
        guard phase != .off, phase != .failed else { return false }
        guard let sessionExpiresAt else { return true }
        return sessionExpiresAt > Date()
    }
}

final class SharedDictationStore {
    static let appGroupID = "group.com.fanpit.LazyFlow"
    static let sessionDuration: TimeInterval = 30 * 60

    private enum Key {
        static let phase = "dictation.phase"
        static let tone = "dictation.tone"
        static let command = "dictation.command"
        static let commandID = "dictation.commandID"
        static let result = "dictation.result"
        static let resultID = "dictation.resultID"
        static let error = "dictation.error"
        static let audioLevel = "dictation.audioLevel"
        static let sessionExpiresAt = "dictation.sessionExpiresAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: Self.appGroupID)
            ?? .standard
    }

    var hasSharedContainer: Bool {
        FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID
        ) != nil
    }

    func snapshot() -> DictationSnapshot {
        DictationSnapshot(
            phase: DictationPhase(rawValue: defaults.string(forKey: Key.phase) ?? "") ?? .off,
            tone: MobileTone(rawValue: defaults.string(forKey: Key.tone) ?? "") ?? .clean,
            command: DictationCommand(rawValue: defaults.string(forKey: Key.command) ?? "") ?? .none,
            commandID: defaults.string(forKey: Key.commandID) ?? "",
            result: defaults.string(forKey: Key.result) ?? "",
            resultID: defaults.string(forKey: Key.resultID) ?? "",
            errorMessage: defaults.string(forKey: Key.error) ?? "",
            audioLevel: defaults.double(forKey: Key.audioLevel),
            sessionExpiresAt: defaults.object(forKey: Key.sessionExpiresAt) as? Date
        )
    }

    @discardableResult
    func request(_ command: DictationCommand) -> String {
        let identifier = UUID().uuidString
        defaults.set(command.rawValue, forKey: Key.command)
        defaults.set(identifier, forKey: Key.commandID)
        defaults.synchronize()
        return identifier
    }

    func setTone(_ tone: MobileTone) {
        defaults.set(tone.rawValue, forKey: Key.tone)
        defaults.synchronize()
    }

    func setPhase(
        _ phase: DictationPhase,
        errorMessage: String = "",
        renewSession: Bool = false
    ) {
        defaults.set(phase.rawValue, forKey: Key.phase)
        defaults.set(errorMessage, forKey: Key.error)
        if renewSession {
            defaults.set(Date().addingTimeInterval(Self.sessionDuration), forKey: Key.sessionExpiresAt)
        }
        defaults.synchronize()
    }

    func setAudioLevel(_ level: Double) {
        defaults.set(max(0, min(level, 1)), forKey: Key.audioLevel)
    }

    func publish(_ text: String) {
        defaults.set(text, forKey: Key.result)
        defaults.set(UUID().uuidString, forKey: Key.resultID)
        defaults.set(DictationPhase.resultReady.rawValue, forKey: Key.phase)
        defaults.synchronize()
    }

    func acknowledgeResult() {
        defaults.set("", forKey: Key.result)
        defaults.set(DictationPhase.ready.rawValue, forKey: Key.phase)
        defaults.synchronize()
    }

    func clearSession() {
        defaults.set(DictationPhase.off.rawValue, forKey: Key.phase)
        defaults.set(DictationCommand.none.rawValue, forKey: Key.command)
        defaults.set("", forKey: Key.commandID)
        defaults.set("", forKey: Key.result)
        defaults.set("", forKey: Key.resultID)
        defaults.set("", forKey: Key.error)
        defaults.set(0, forKey: Key.audioLevel)
        defaults.removeObject(forKey: Key.sessionExpiresAt)
        defaults.synchronize()
    }
}
