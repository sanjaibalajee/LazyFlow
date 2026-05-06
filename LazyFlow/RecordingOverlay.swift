import SwiftUI
import AppKit

// MARK: - Controller

final class RecordingOverlayController {
    private var panel: NSPanel?

    func show(audioLevel: Float = 0) {
        if panel != nil { return }

        let hosting = NSHostingView(rootView: RecordingOverlayView())
        hosting.frame = NSRect(x: 0, y: 0, width: 180, height: 52)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.isFloatingPanel      = true
        p.level                = .floating
        p.backgroundColor      = .clear
        p.isOpaque             = false
        p.hasShadow            = true
        p.ignoresMouseEvents   = true
        p.collectionBehavior   = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView          = hosting

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - hosting.frame.width / 2
            let y = screen.visibleFrame.minY + 48
            p.setFrameOrigin(NSPoint(x: x, y: y))
        }

        p.alphaValue = 0
        p.orderFront(nil)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            p.animator().alphaValue = 1
        }
        panel = p
    }

    func hide() {
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            p.animator().alphaValue = 0
        }, completionHandler: {
            p.orderOut(nil)
        })
    }
}

// MARK: - View

struct RecordingOverlayView: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 22, height: 22)
                    .scaleEffect(pulse ? 1.4 : 1.0)

                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
            }

            Text("Listening…")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.regularMaterial, in: Capsule())
        .onAppear {
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
