import AppKit
import SwiftUI

// MARK: - Keyable borderless panel

private final class AgentPanel: NSPanel {
    override var canBecomeKey: Bool  { true  }
    override var canBecomeMain: Bool { false }
}

// MARK: - Controller

final class AgentWindowController {
    private let agentState: AgentState
    private let appState:   AppState
    private var panel:      AgentPanel?

    static let width: CGFloat = 500

    init(agentState: AgentState, appState: AppState) {
        self.agentState = agentState
        self.appState   = appState
    }

    // MARK: - Show / hide

    func show() {
        guard panel == nil else { return }

        let root = AgentWindowView()
            .environment(agentState)
            .environment(appState)
        let hosting = NSHostingView(rootView: root)

        // Measure natural height before committing
        let natural = hosting.fittingSize
        let initial = NSRect(x: 0, y: 0, width: Self.width, height: max(44, natural.height))
        hosting.frame = initial

        let p = AgentPanel(contentRect: initial, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        p.isFloatingPanel             = true
        p.level                       = .floating
        p.backgroundColor             = .clear
        p.isOpaque                    = false
        p.hasShadow                   = true
        p.isMovableByWindowBackground = true
        p.collectionBehavior          = [.canJoinAllSpaces, .stationary]
        p.contentView                 = hosting

        // Top-centre of screen
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - Self.width / 2
            let y = screen.visibleFrame.maxY - 160
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.alphaValue = 0
        p.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p

        Task { @MainActor [weak self] in await self?.watchPhase() }
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }

    func releaseKeyFocus() { panel?.resignKey() }

    // MARK: - Phase watcher + auto-resize

    @MainActor
    private func watchPhase() async {
        var lastKey = ""
        while panel != nil {
            let key = phaseKey(agentState.phase)
            if key != lastKey {
                lastKey = key
                fitToContent()
                switch agentState.phase {
                case .running:
                    releaseKeyFocus()
                default: break
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func phaseKey(_ p: AgentState.Phase) -> String {
        switch p {
        case .idle:          return "idle"
        case .enteringGoal:  return "goal"
        case .running:       return "run-\(agentState.steps.count)-\(agentState.isBlocked)"
        case .done(let s):   return "done\(s.hashValue)"
        case .failed(let s): return "fail\(s.hashValue)"
        }
    }

    func fitToContent() {
        guard let p = panel, let hosting = p.contentView else { return }
        let fit = hosting.fittingSize
        let h   = max(56, min(fit.height, 620))
        guard abs(h - p.frame.height) > 1 else { return }
        var fr = p.frame
        fr.origin.y  -= (h - fr.height)
        fr.size       = NSSize(width: Self.width, height: h)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().setFrame(fr, display: true)
        }
    }
}
