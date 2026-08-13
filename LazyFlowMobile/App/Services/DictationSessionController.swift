import Foundation
import SwiftUI

@MainActor
final class DictationSessionController: ObservableObject {
    @Published private(set) var phase: DictationPhase
    @Published private(set) var errorMessage = ""
    @Published private(set) var level = 0.0
    @Published var tone: MobileTone {
        didSet { store.setTone(tone) }
    }

    private let store: SharedDictationStore
    private let audio: AudioSessionController
    private let engine: NativeLazyFlowEngine
    private var processedCommandID: String
    private var monitorTask: Task<Void, Never>?
    private var processingTask: Task<Void, Never>?

    init(
        store: SharedDictationStore = SharedDictationStore(),
        audio: AudioSessionController? = nil,
        engine: NativeLazyFlowEngine = NativeLazyFlowEngine()
    ) {
        self.store = store
        self.audio = audio ?? AudioSessionController()
        self.engine = engine
        let snapshot = store.snapshot()
        phase = snapshot.isSessionActive ? snapshot.phase : .off
        tone = snapshot.tone
        processedCommandID = snapshot.commandID
    }

    deinit {
        monitorTask?.cancel()
        processingTask?.cancel()
    }

    var isSessionActive: Bool { phase != .off }
    var isRecording: Bool { phase == .recording }
    var hasSharedContainer: Bool { store.hasSharedContainer }

    func startMonitoring() {
        guard monitorTask == nil else { return }
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .milliseconds(120))
            }
        }
    }

    func startSession() async {
        guard phase == .off || phase == .failed else { return }
        phase = .preparing
        errorMessage = ""
        store.setPhase(.preparing, renewSession: true)

        do {
            try await audio.arm()
            phase = .ready
            store.setPhase(.ready, renewSession: true)
        } catch {
            fail(with: error)
        }
    }

    func endSession() {
        processingTask?.cancel()
        processingTask = nil
        audio.disarm()
        level = 0
        errorMessage = ""
        phase = .off
        store.clearSession()
    }

    func retry() async {
        endSession()
        await startSession()
    }

    private func poll() {
        let snapshot = store.snapshot()
        if snapshot.tone != tone {
            tone = snapshot.tone
        }
        if phase == .resultReady, snapshot.phase == .ready {
            phase = .ready
        }
        if snapshot.sessionExpiresAt.map({ $0 <= Date() }) == true {
            endSession()
            return
        }

        let smoothedLevel = audio.level
        if level != smoothedLevel {
            level = smoothedLevel
            store.setAudioLevel(smoothedLevel)
        }

        guard !snapshot.commandID.isEmpty,
              snapshot.commandID != processedCommandID else { return }
        processedCommandID = snapshot.commandID

        switch snapshot.command {
        case .start:
            beginUtterance()
        case .stop:
            finishUtterance()
        case .cancel:
            cancelUtterance()
        case .endSession:
            endSession()
        case .none:
            break
        }
    }

    private func beginUtterance() {
        guard phase == .ready || phase == .resultReady else { return }
        do {
            try audio.beginRecording()
            phase = .recording
            store.setPhase(.recording, renewSession: true)
        } catch {
            fail(with: error)
        }
    }

    private func finishUtterance() {
        guard phase == .recording else { return }
        do {
            let url = try audio.finishRecording()
            phase = .processing
            store.setPhase(.processing, renewSession: true)
            let selectedTone = tone
            processingTask = Task { [weak self] in
                guard let self else { return }
                defer { try? FileManager.default.removeItem(at: url) }
                do {
                    let text = try await engine.transcribeAndRefine(
                        recordingAt: url,
                        tone: selectedTone
                    )
                    guard !Task.isCancelled else { return }
                    phase = .resultReady
                    store.publish(text)
                } catch is CancellationError {
                    return
                } catch {
                    fail(with: error)
                }
            }
        } catch {
            fail(with: error)
        }
    }

    private func cancelUtterance() {
        processingTask?.cancel()
        processingTask = nil
        audio.cancelRecording()
        phase = .ready
        store.setPhase(.ready, renewSession: true)
    }

    private func fail(with error: Error) {
        audio.cancelRecording()
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        phase = .failed
        store.setPhase(.failed, errorMessage: errorMessage)
    }
}
