import Foundation
import SwiftUI

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var snapshot: DictationSnapshot
    @Published private(set) var hasFullAccess: Bool
    @Published private(set) var hasSharedContainer: Bool
    @Published private(set) var handoffMessage = ""
    @Published private(set) var isOpeningApp = false

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

    func prepareAppHandoff() {
        handoffMessage = ""
        isOpeningApp = true
        store.request(.beginSession)
    }

    func completeAppHandoff(opened: Bool, notificationScheduled: Bool = false) {
        isOpeningApp = false
        if notificationScheduled {
            handoffMessage = "Tap the LazyFlow notification, then swipe back here when the session is ready."
        } else if !opened {
            handoffMessage = "iOS couldn’t open LazyFlow from this keyboard. Open the app once, start a voice session, then come back."
        }
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
