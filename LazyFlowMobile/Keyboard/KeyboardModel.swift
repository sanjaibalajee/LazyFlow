import Foundation
import SwiftUI

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var snapshot: DictationSnapshot
    @Published private(set) var hasFullAccess: Bool
    @Published private(set) var hasSharedContainer: Bool
    @Published private(set) var launchMessage = ""
    @Published private(set) var isRequestingLaunch = false

    private let store: SharedDictationStore
    private let insertText: (String) -> Void
    private let sharedContainerOverride: Bool?
    private var lastResultID = ""
    private var monitorTask: Task<Void, Never>?

    init(
        hasFullAccess: Bool,
        store: SharedDictationStore = SharedDictationStore(),
        sharedContainerAvailable: Bool? = nil,
        insertText: @escaping (String) -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.store = store
        sharedContainerOverride = sharedContainerAvailable
        self.insertText = insertText
        hasSharedContainer = sharedContainerAvailable ?? store.hasSharedContainer
        snapshot = store.snapshot()
        lastResultID = snapshot.resultID
        startMonitoring()
    }

    deinit { monitorTask?.cancel() }

    func updateFullAccess(_ value: Bool) {
        hasFullAccess = value
        hasSharedContainer = sharedContainerOverride ?? store.hasSharedContainer
    }

    func selectTone(_ tone: MobileTone) {
        store.setTone(tone)
        snapshot.tone = tone
    }

    func toggleRecording() {
        switch snapshot.phase {
        case .ready, .resultReady:
            store.request(.start)
        case .recording:
            store.request(.stop)
        default:
            break
        }
    }

    func cancel() {
        store.request(.cancel)
    }

    func endSession() {
        store.request(.endSession)
    }

    @discardableResult
    func prepareVoiceSessionRequest() -> String {
        launchMessage = ""
        isRequestingLaunch = true
        let commandID = store.request(.beginSession)
        KeyboardHandoffDiagnostics.record(
            .bridge,
            "Keyboard wrote begin-session command",
            details: "commandID=\(commandID), appGroup=\(hasSharedContainer), fullAccess=\(hasFullAccess)"
        )
        return commandID
    }

    func completeVoiceSessionRequest(notificationScheduled: Bool) {
        isRequestingLaunch = false
        launchMessage = notificationScheduled
            ? "Tap the notification to open LazyFlow."
            : "Allow LazyFlow notifications, then try again."
    }

    private func startMonitoring() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refresh()
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    private func refresh() {
        let latest = store.snapshot()
        snapshot = latest

        guard latest.phase == .resultReady,
              !latest.result.isEmpty,
              latest.resultID != lastResultID else { return }
        lastResultID = latest.resultID
        insertText(latest.result)
        store.acknowledgeResult()
    }
}
