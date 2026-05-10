import AppKit
import AVFoundation

class AppDelegate: NSObject, NSApplicationDelegate {
    let appState               = AppState()
    private let hotkeyManager  = HotkeyManager()
    private lazy var overlay   = RecordingOverlayController(appState: appState)

    // Computer Use
    private let agentState          = AgentState()
    private lazy var agentWindow    = AgentWindowController(agentState: agentState, appState: appState)
    private var computerUseService: ComputerUseService?
    private var agentTargetPid:     pid_t = 0   // captured before window steals focus

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestMicrophonePermission()
        setupHotkeys()
        observeRecordingState()
        appState.setupLocalServicesIfNeeded()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    // MARK: - Permissions

    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    // MARK: - Hotkeys

    private func setupHotkeys() {
        hotkeyManager.onStartRecording  = { [weak self] in self?.appState.startRecording() }
        hotkeyManager.onStopRecording   = { [weak self] in self?.appState.stopRecording() }
        hotkeyManager.onCancelRecording = { [weak self] in self?.appState.cancelRecording() }
        hotkeyManager.onToggleModeActive = { [weak self] active in
            DispatchQueue.main.async { self?.appState.isToggleMode = active }
        }
        hotkeyManager.onAgentMode = { [weak self] in
            DispatchQueue.main.async { self?.startAgentGoalEntry() }
        }

        // When recording is cancelled via the UI cancel button, reset hotkey state too
        appState.onRecordingCancelled = { [weak self] in
            DispatchQueue.main.async { self?.hotkeyManager.forceReset() }
        }

        do {
            try hotkeyManager.start()
        } catch {
            showPermissionAlert(message: error.localizedDescription)
        }
    }

    // MARK: - Overlay

    private func observeRecordingState() {
        appState.onRecordingChanged = { [weak self] recording in
            DispatchQueue.main.async {
                // Don't show the dictation overlay during goal recording
                guard self?.appState.goalRecordingMode != true else { return }
                if recording { self?.overlay.show() } else { self?.overlay.hide() }
            }
        }
    }

    // MARK: - Computer Use

    private func startAgentGoalEntry() {
        // Capture target app NOW — before window appears and steals frontmost status
        agentTargetPid = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        print("[Agent] 🎯 captured target pid \(agentTargetPid) (\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"))")

        agentState.reset()
        agentState.phase = .enteringGoal

        agentState.onApprove = { [weak self] in
            let goal = self?.agentState.goal.trimmingCharacters(in: .whitespaces) ?? ""
            guard !goal.isEmpty else { return }
            self?.startAgentRun(goal: goal)
        }
        agentState.onCancel = { [weak self] in
            self?.agentWindow.hide()
            self?.agentState.reset()
        }

        agentWindow.show()
    }

    private func startAgentRun(goal: String) {
        var agentCfg = appState.providerStore.config(for: .agent)
        // Fall back to Groq with legacy key if provider store has no key yet
        if agentCfg.apiKey.isEmpty && !appState.apiKey.isEmpty {
            agentCfg = LLMConfig(
                provider:  .groq,
                baseURL:   LLMProvider.groq.defaultBaseURL,
                apiKey:    appState.apiKey,
                model:     "meta-llama/llama-4-scout-17b-16e-instruct",
                modelSpec: LLMProvider.groq.presetModels.first { $0.vision && $0.tools }
            )
        }
        guard !agentCfg.apiKey.isEmpty else { return }

        agentState.phase = .running
        agentState.steps = []

        let service = ComputerUseService(
            config:    agentCfg,
            kbContext: appState.knowledgeStore.contextBlock,
            targetPid: agentTargetPid,
            onEvent:   { [weak self] event in self?.agentState.apply(event) }
        )
        computerUseService = service

        // Wire approval / clarification / cancel callbacks
        agentState.onApprove = { Task { await service.approve() } }
        agentState.onReject  = { Task { await service.reject() } }
        agentState.onAnswerClarification = { text in Task { await service.answerClarification(text) } }
        agentState.onCancel = { [weak self] in
            Task { await service.cancel() }
            self?.agentWindow.hide()
            self?.agentState.reset()
        }

        Task {
            await service.run(goal: goal)
        }
    }

    // MARK: - Alert

    private func showPermissionAlert(message: String) {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText     = "Permission Required"
            alert.informativeText = message
            alert.alertStyle      = .warning
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(
                    URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
                )
            }
        }
    }
}
