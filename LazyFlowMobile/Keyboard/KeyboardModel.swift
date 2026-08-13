import Foundation
import SwiftUI

@MainActor
final class KeyboardModel: ObservableObject {
    @Published private(set) var snapshot: DictationSnapshot
    @Published private(set) var hasFullAccess: Bool

    private let store: SharedDictationStore
    private let insertText: (String) -> Void
    private var lastResultID = ""
    private var monitorTask: Task<Void, Never>?

    init(
        hasFullAccess: Bool,
        store: SharedDictationStore = SharedDictationStore(),
        insertText: @escaping (String) -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.store = store
        self.insertText = insertText
        snapshot = store.snapshot()
        lastResultID = snapshot.resultID
        startMonitoring()
    }

    deinit { monitorTask?.cancel() }

    func updateFullAccess(_ value: Bool) {
        hasFullAccess = value
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
