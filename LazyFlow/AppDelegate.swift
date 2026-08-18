import AppKit

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
        appState.refreshPermissions()
        configureHotkeys()
        observeRecordingState()
        appState.setupLocalServicesIfNeeded()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Permission changes happen in System Settings while LazyFlow is inactive.
        // Refresh and install the global monitor immediately when the user returns.
        appState.refreshPermissions()
        configureHotkeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager.stop()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// Keep the menu-bar app and its global hotkeys alive while moving all app
    /// windows out of the way. The explicit menu-bar Quit action still performs
    /// a real termination, which Sparkle also needs when installing an update.
    func runInBackground() {
        NSApp.hide(nil)
    }

    // MARK: - Hotkeys

    private func configureHotkeys() {
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

        guard appState.hasAccessibilityPermission else {
            hotkeyManager.stop()
            return
        }

        do { try hotkeyManager.start() }
        catch { appState.errorMessage = error.localizedDescription }
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

}
