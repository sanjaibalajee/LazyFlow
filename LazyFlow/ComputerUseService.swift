import Foundation
import AppKit

// MARK: - Groq tool definitions

private let agentTools: [[String: Any]] = [
    tool("see",   "Capture a screenshot and read all interactive UI elements of the frontmost app. Call after every action.",
         params: [:], required: []),
    tool("open_app", "Launch or switch to a macOS application by name (e.g. 'WhatsApp', 'Safari', 'Mail', 'Notes'). Use this before interacting with any app that is not currently visible.",
         params: ["name": ["type": "string", "description": "App name as it appears in the Dock or /Applications"]], required: ["name"]),
    tool("click", "Click a UI element by its ID from the last see() call. Prefer this over click_coords whenever an element ID is available.",
         params: ["elementId": ["type": "string", "description": "Element ID e.g. elem_3"]], required: ["elementId"]),
    tool("double_click", "Double-click a UI element by its ID. Use for list items, contacts, or files that require double-click to open.",
         params: ["elementId": ["type": "string", "description": "Element ID from last see() call"]], required: ["elementId"]),
    tool("click_coords", "Click at a screen coordinate. Use ONLY when the target is not in the see() element list (e.g. canvas, Electron UI). Coordinates: x from left, y from top, in logical screen points (see() includes screen dimensions).",
         params: [
             "x": ["type": "integer", "description": "Logical points from left edge"],
             "y": ["type": "integer", "description": "Logical points from top edge (0 = top)"],
         ], required: ["x", "y"]),
    tool("type",  "Type text into the focused element, optionally clicking one first.",
         params: ["text": ["type": "string"], "elementId": ["type": "string", "description": "Optional: click this element before typing"]], required: ["text"]),
    tool("press_key", "Press a key or shortcut. Supported: return, tab, escape, space, delete, forward_delete, up, down, left, right, home, end, pageup, pagedown, cmd+a/c/v/x/z/s/f/w/n/t/r/l/q, cmd+tab (switch app), cmd+` (switch window), cmd+shift+z/tab, cmd+left/right/up/down, opt+left/right",
         params: ["key": ["type": "string"]], required: ["key"]),
    tool("scroll", "Scroll the current view.",
         params: ["direction": ["type": "string", "enum": ["up", "down"]], "lines": ["type": "integer", "description": "Lines (default 3)"]], required: ["direction"]),
    tool("wait", "Wait for the UI to finish loading or animating. Use after open_app if the app needs extra time.",
         params: ["seconds": ["type": "number", "description": "Seconds to wait (0.5 – 8)"]], required: ["seconds"]),
    tool("ask_clarification", "Ask the user a question when you need more information.",
         params: ["question": ["type": "string"]], required: ["question"]),
    tool("done", "Signal that the task is complete.",
         params: ["summary": ["type": "string"]], required: ["summary"]),
]

private func tool(_ name: String, _ description: String, params: [String: Any], required: [String]) -> [String: Any] {
    ["type": "function", "function": [
        "name": name,
        "description": description,
        "parameters": ["type": "object", "properties": params, "required": required],
    ]]
}

// MARK: - Service

actor ComputerUseService {
    private let config:    LLMConfig
    private let kbContext: String?
    private let targetPid: pid_t

    private var pendingApproval:      CheckedContinuation<Bool, Never>?
    private var pendingClarification: CheckedContinuation<String, Never>?
    private var isCancelled = false

    private var snapshotCache: [DetectedElement] = []
    private var lastSeenPid:   pid_t = 0   // frontmost app at the time of last see()

    // The pid to send input to — dynamically tracked, falls back to the original target
    private var activePid: pid_t { lastSeenPid > 0 ? lastSeenPid : targetPid }

    var onEvent: @MainActor @Sendable (AgentEvent) -> Void

    init(config: LLMConfig, kbContext: String?, targetPid: pid_t,
         onEvent: @escaping @MainActor @Sendable (AgentEvent) -> Void = { _ in }) {
        self.config   = config
        self.kbContext = kbContext
        self.targetPid = targetPid
        self.onEvent   = onEvent
        print("[Agent] 🎯 Target pid: \(targetPid) | \(config.provider.displayName) / \(config.model)")
    }

    // MARK: - Control

    func cancel() {
        isCancelled = true
        pendingApproval?.resume(returning: false);       pendingApproval      = nil
        pendingClarification?.resume(returning: "");    pendingClarification = nil
    }

    func approve() {
        pendingApproval?.resume(returning: true);  pendingApproval = nil
    }

    func reject() {
        pendingApproval?.resume(returning: false); pendingApproval = nil
    }

    func answerClarification(_ text: String) {
        pendingClarification?.resume(returning: text); pendingClarification = nil
    }

    // MARK: - Main loop

    func run(goal: String) async {
        isCancelled = false

        // Call see() once upfront and inject the result as the first user message
        let initialScreen = await doSee()
        var messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt()],
            ["role": "user",   "content": "Goal: \(goal)\n\nCurrent screen:\n\(initialScreen)"],
        ]
        // Inject screenshot if captured during initial see()
        if let b64 = lastScreenshot, config.supportsVision {
            messages.append([
                "role": "user",
                "content": [
                    ["type": "text",      "text": "Current screen screenshot:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
                ] as [[String: Any]],
            ])
            lastScreenshot = nil
        }

        for iteration in 0..<40 {
            guard !isCancelled else { await emit(.cancelled); return }

            await emit(.turnCount(iteration + 1))

            let response: GroqResponse
            do {
                response = try await callGroqWithRetry(messages: messages, toolChoice: "required")
            } catch {
                await emit(.failed("Network error: \(error.localizedDescription)")); return
            }

            // Surface LLM reasoning text in the UI
            if let thought = response.content, !thought.isEmpty {
                print("[Agent] 💭 \(thought)")
                await emit(.thought(thought))
            }

            guard let toolCalls = response.toolCalls, !toolCalls.isEmpty else {
                await emit(.done(response.content ?? "Done")); return
            }

            // Add assistant turn to history
            var assistantMsg: [String: Any] = ["role": "assistant", "content": response.content as Any]
            assistantMsg["tool_calls"] = toolCalls.map { tc -> [String: Any] in
                ["id": tc.id, "type": "function",
                 "function": ["name": tc.name, "arguments": encodeArgs(tc.arguments)]]
            }
            messages.append(assistantMsg)

            // Execute each tool call
            for tc in toolCalls {
                guard !isCancelled else { break }
                let result = await executeToolCall(tc)
                messages.append(["role": "tool", "tool_call_id": tc.id, "content": result])
                if tc.name == "done" { return }
            }
        }

        await emit(.done("Reached maximum steps"))
    }

    // MARK: - Tool execution

    private func executeToolCall(_ tc: AgentToolCall) async -> String {
        let stepId = UUID()
        let started = Date()
        await emit(.stepStarted(AgentStep(id: stepId, tool: tc.name, description: stepDescription(tc))))
        let result = await performTool(tc, stepId: stepId)
        let elapsed = Date().timeIntervalSince(started)
        if result.hasPrefix("Error:") {
            await emit(.stepUpdated(id: stepId, status: .failed(result)))
        } else if tc.name != "ask_clarification" {
            await emit(.stepUpdated(id: stepId, status: .done(elapsed)))
        }
        return result
    }

    private func performTool(_ tc: AgentToolCall, stepId: UUID) async -> String {
        switch tc.name {

        case "see":
            return await doSee()

        case "open_app":
            guard let appName = tc.arg("name") else { return "Error: Missing name" }
            print("[Agent] 🚀 open_app \"\(appName)\"")
            await MainActor.run {
                let task = Process()
                task.launchPath = "/usr/bin/open"
                task.arguments  = ["-a", appName]
                try? task.run()
            }
            // Wait for the app to launch and become frontmost
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            return "Opened \"\(appName)\" — call see() to observe it"

        case "click":
            guard let elemId = tc.arg("elementId") else { return "Error: Missing elementId" }
            guard let element = snapshotCache.first(where: { $0.id == elemId })
            else { return "Error: Element \(elemId) not found — call see() first (cache has \(snapshotCache.count) elements)" }

            print("[Agent] 👆 click \(elemId) '\(element.label ?? "?")' at \(element.bounds)")

            if element.requiresApproval {
                let label = element.label ?? element.id
                await emit(.approvalRequired(id: stepId, action: "Click \"\(label)\""))
                let approved = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
                    pendingApproval = cont
                }
                guard approved else { return "Error: User declined clicking \"\(label)\"" }
            }

            let center  = CGPoint(x: element.bounds.midX, y: element.bounds.midY)
            let clickPid = activePid
            await MainActor.run {
                NSRunningApplication(processIdentifier: clickPid)?.activate()
                Thread.sleep(forTimeInterval: 0.08)
                AgentInputDriver.click(at: center)
            }
            print("[Agent] ✅ clicked '\(element.label ?? elemId)'")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            return "Clicked \"\(element.label ?? elemId)\" — waited 1.5s for page transition"

        case "double_click":
            guard let elemId = tc.arg("elementId") else { return "Error: Missing elementId" }
            guard let element = snapshotCache.first(where: { $0.id == elemId })
            else { return "Error: Element \(elemId) not found — call see() first" }

            print("[Agent] 👆👆 double_click \(elemId) '\(element.label ?? "?")'")
            let dcCenter = CGPoint(x: element.bounds.midX, y: element.bounds.midY)
            let dcPid = activePid
            await MainActor.run {
                NSRunningApplication(processIdentifier: dcPid)?.activate()
                Thread.sleep(forTimeInterval: 0.08)
                AgentInputDriver.doubleClick(at: dcCenter)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return "Double-clicked \"\(element.label ?? elemId)\""

        case "click_coords":
            guard let xStr = tc.arg("x"), let yStr = tc.arg("y"),
                  let xi = Double(xStr), let yi = Double(yStr) else {
                return "Error: Missing or invalid x/y coordinates"
            }
            print("[Agent] 🎯 click_coords (\(Int(xi)), \(Int(yi)))")
            let ccPid = activePid
            await MainActor.run {
                NSRunningApplication(processIdentifier: ccPid)?.activate()
                Thread.sleep(forTimeInterval: 0.08)
                // Convert from visual (y from top) to Quartz (y from bottom)
                let screenH = NSScreen.main?.frame.height ?? 900
                let quartzPt = CGPoint(x: xi, y: screenH - yi)
                AgentInputDriver.click(at: quartzPt)
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            return "Clicked at screen (\(Int(xi)), \(Int(yi)))"

        case "type":
            guard let text = tc.arg("text") else { return "Error: Missing text" }
            print("[Agent] ⌨️  type \"\(text.prefix(40))\"")
            let typePid = activePid

            if let elemId = tc.arg("elementId"),
               let element = snapshotCache.first(where: { $0.id == elemId }) {
                let center = CGPoint(x: element.bounds.midX, y: element.bounds.midY)
                await MainActor.run {
                    NSRunningApplication(processIdentifier: typePid)?.activate()
                    Thread.sleep(forTimeInterval: 0.08)
                    AgentInputDriver.click(at: center)
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }

            await MainActor.run { AgentInputDriver.type(text: text) }
            return "Typed \"\(text.prefix(40))\""

        case "press_key":
            guard let key = tc.arg("key") else { return "Error: Missing key" }
            let keyPid = activePid
            await MainActor.run {
                NSRunningApplication(processIdentifier: keyPid)?.activate()
                Thread.sleep(forTimeInterval: 0.05)
                AgentInputDriver.pressKey(key)
            }
            return "Pressed \(key)"

        case "scroll":
            let dir      = tc.arg("direction") ?? "down"
            let lines    = Int(tc.arg("lines") ?? "3") ?? 3
            let scrollPid = activePid
            await MainActor.run {
                NSRunningApplication(processIdentifier: scrollPid)?.activate()
                Thread.sleep(forTimeInterval: 0.05)
                AgentInputDriver.scroll(direction: dir, lines: lines)
            }
            return "Scrolled \(dir) \(lines) lines"

        case "wait":
            let rawSecs = Double(tc.arg("seconds") ?? "2") ?? 2
            let secs    = min(8, max(0.5, rawSecs))
            print("[Agent] ⏳ wait \(secs)s")
            try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
            return "Waited \(String(format: "%.1f", secs))s"

        case "ask_clarification":
            guard let question = tc.arg("question") else { return "Error: " + "Missing question" }
            await emit(.clarificationRequired(id: stepId, question: question))
            let answer = await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
                pendingClarification = cont
            }
            guard !isCancelled, !answer.isEmpty else { return "Error: " + "No answer provided" }
            return "User answered: \(answer)"

        case "done":
            let summary = tc.arg("summary") ?? "Task complete"
            await emit(.done(summary))
            return summary

        default:
            return "Error: " + "Unknown tool: \(tc.name)"
        }
    }

    // MARK: - See implementation (AX snapshot + screenshot, with retry on 0 elements)

    private func doSee() async -> String {
        // Capture actor state before hopping to main actor
        let capturedLastPid   = lastSeenPid
        let capturedTargetPid = targetPid

        // Detect the current frontmost app, skipping LazyFlow itself
        let (pid, appName) = await MainActor.run { () -> (pid_t, String) in
            let ourBundle = Bundle.main.bundleIdentifier ?? ""
            if let front = NSWorkspace.shared.frontmostApplication,
               front.bundleIdentifier != ourBundle,
               front.processIdentifier > 0 {
                return (front.processIdentifier, front.localizedName ?? "?")
            }
            // Fall back to last-seen or original target
            let fb = capturedLastPid > 0 ? capturedLastPid : capturedTargetPid
            return (fb, NSRunningApplication(processIdentifier: fb)?.localizedName ?? "?")
        }
        lastSeenPid = pid
        print("[Agent] 👁 see() — pid \(pid) (\(appName))")

        var elements: [DetectedElement] = await MainActor.run {
            guard pid > 0, let app = NSRunningApplication(processIdentifier: pid) else {
                print("[Agent] ⚠️ see() — no running app for pid \(pid)")
                return []
            }
            return AXSnapshotService.snapshot(for: app)
        }

        // Retry once — page may still be loading
        if elements.isEmpty {
            print("[Agent] 👁 see() — 0 elements, waiting 1.5s and retrying…")
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            elements = await MainActor.run {
                guard let app = NSRunningApplication(processIdentifier: pid) else { return [] }
                return AXSnapshotService.snapshot(for: app)
            }
        }

        snapshotCache = elements
        print("[Agent] 👁 see() — found \(elements.count) elements")
        for e in elements.prefix(8) { print("  \(e.id): \(e.elementDescription)") }

        let screenshot = await ScreenshotService.captureFrontmost()
        let screenshotSize = screenshot.map { "\($0.count / 1024)KB" } ?? "nil"
        print("[Agent] 📸 screenshot: \(screenshotSize)")
        lastScreenshot = screenshot

        let (screenW, screenH) = await MainActor.run {
            let r = NSScreen.main?.frame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
            return (Int(r.width), Int(r.height))
        }

        let elemList = elements.isEmpty
            ? "No AX-accessible elements detected (Electron/canvas app). Use click_coords with the screenshot to interact."
            : elements.map { "\($0.id): \($0.elementDescription)" }.joined(separator: "\n")

        let coordNote = "Screen: \(screenW)×\(screenH)pt — click_coords uses (x from left, y from top) in these units."
        let elemNote  = elements.isEmpty ? "" : "\nPrefer click(elementId) over click_coords when an ID is available."
        return "Screen observed [\(appName)]. \(elements.count) interactive elements:\n\(elemList)\n\(coordNote)\(elemNote)"
    }

    // Latest screenshot stored so it can be injected with the next Groq call
    private var lastScreenshot: String? = nil

    // MARK: - LLM API (via shared LLMClient)

    // GroqResponse typealiased to LLMClient.ToolsResponse for naming consistency
    private typealias GroqResponse = LLMClient.ToolsResponse

    private func callGroqWithRetry(messages: [[String: Any]], toolChoice: Any) async throws -> GroqResponse {
        // Inject screenshot as vision message when available
        var enrichedMessages = messages
        if let b64 = lastScreenshot, config.supportsVision {
            enrichedMessages.append([
                "role": "user",
                "content": [
                    ["type": "text",      "text": "Current screen screenshot:"],
                    ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(b64)"]],
                ] as [[String: Any]],
            ])
            lastScreenshot = nil
        }

        print("[Agent] 🌐 → \(config.provider.displayName) (\(enrichedMessages.count) messages)")
        let client = LLMClient(config: config)
        let resp = try await client.withRetry {
            try await client.chatWithTools(
                messages: enrichedMessages,
                tools: agentTools,
                toolChoice: toolChoice,
                temperature: 0.1
            )
        }
        print("[Agent] 🔧 tool calls: \(resp.toolCalls?.map(\.name).joined(separator: ", ") ?? "none")")
        return resp
    }

    // MARK: - Helpers

    private func emit(_ event: AgentEvent) async {
        let handler = onEvent   // capture on actor before crossing to MainActor
        await MainActor.run { handler(event) }
    }

    private func systemPrompt() -> String {
        var prompt = """
        You are a macOS computer-use agent. Complete the user's goal by calling tools to interact with the screen.

        RULES:
        1. The current screen state is already provided with your goal — do NOT call see() as your very first action unless instructed. Call see() after every action to verify the result.
        2. AMBIGUITY: If the goal requires choosing between multiple options (events, products, forms, people) and the user did not specify which one, call ask_clarification() before acting. Never pick one at random.
        3. UNKNOWN ELEMENTS: If you cannot identify what a UI element does from its label, do not click it. Either scroll to find something more clearly labelled, or call ask_clarification().
        4. FORMS: When filling a form, type into each field using its elementId. Do not type without an elementId unless the field is already focused.
        5. TYPING: Always type the complete text in a SINGLE type() call. Never split a message, sentence, or word across multiple calls. One field = one type() call with the full value.
        6. ELECTRON/CANVAS APPS: If see() returns no elements or coordinates look wrong, use the screenshot and click_coords() to interact. click_coords x/y are logical screen points (see screen dimensions in see() output), y increases downward from the top.
        7. DESTRUCTIVE ACTIONS: Clicking Submit, Send, Delete, Buy, Confirm will prompt the user for approval automatically — you do not need to ask separately.
        8. DONE: Call done() with a clear summary when the goal is fully achieved.
        9. STUCK: If an action has no visible effect after two tries, call done() with an explanation rather than looping.
        """
        if let kb = kbContext {
            prompt += "\n\nUser profile (use to fill forms):\n\(kb)"
        }
        return prompt
    }

    private func stepDescription(_ tc: AgentToolCall) -> String {
        switch tc.name {
        case "see":              return "Capturing screen…"
        case "open_app":        return "Opening \(tc.arg("name") ?? "app")…"
        case "click":           return "Clicking \(tc.arg("elementId") ?? "element")…"
        case "double_click":    return "Double-clicking \(tc.arg("elementId") ?? "element")…"
        case "click_coords":    return "Clicking at (\(tc.arg("x") ?? "?"), \(tc.arg("y") ?? "?"))…"
        case "type":            return "Typing \"\(tc.arg("text")?.prefix(30) ?? "")\"…"
        case "press_key":       return "Pressing \(tc.arg("key") ?? "key")…"
        case "scroll":          return "Scrolling \(tc.arg("direction") ?? "down")…"
        case "wait":            return "Waiting \(tc.arg("seconds") ?? "?")s…"
        case "ask_clarification": return tc.arg("question") ?? "Asking question…"
        case "done":            return tc.arg("summary") ?? "Done"
        default:                return tc.name
        }
    }

    private func encodeArgs(_ args: [String: String]) -> String {
        let json = try? JSONSerialization.data(withJSONObject: args)
        return json.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
