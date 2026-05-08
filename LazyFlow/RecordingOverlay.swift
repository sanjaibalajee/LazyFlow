import SwiftUI
import AppKit

// MARK: - Controller

final class RecordingOverlayController {
    private let appState: AppState
    private var panel: NSPanel?
    private var lastPanelOrigin: NSPoint?  // remembers dragged position within session

    init(appState: AppState) {
        self.appState = appState
    }

    func show() {
        if panel != nil { return }

        let hosting = NSHostingView(rootView: RecordingOverlayView().environment(appState))
        hosting.frame = NSRect(x: 0, y: 0, width: 260, height: 76)

        let p = NSPanel(
            contentRect: hosting.frame,
            styleMask:   [.borderless, .nonactivatingPanel],
            backing:     .buffered,
            defer:       false
        )
        p.isFloatingPanel             = true
        p.level                       = .floating
        p.backgroundColor             = .clear
        p.isOpaque                    = false
        p.hasShadow                   = true
        p.isMovableByWindowBackground = true  // drag anywhere on capsule background
        p.collectionBehavior          = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.contentView                 = hosting

        if let origin = lastPanelOrigin {
            p.setFrameOrigin(origin)
        } else if let screen = NSScreen.main {
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
        lastPanelOrigin = p.frame.origin
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
    @Environment(AppState.self) private var appState

    private var accentColor: Color { appState.isToggleMode ? .orange : .red }

    var body: some View {
        HStack(spacing: 12) {
            WaveformView(level: appState.audioLevel, color: accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isToggleMode ? "Tap ⌥ to stop" : "Listening…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                // Always reserve the second line so capsule height stays stable
                Text(appState.targetAppName.map { "→ \($0)" } ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(appState.targetAppName != nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.clear))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)

            Button {
                appState.cancelRecording()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.primary.opacity(0.1)))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(width: 240)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Waveform

struct WaveformView: View {
    let level: Float
    let color: Color

    // Each bar has its own speed and phase so they animate independently
    private static let multipliers: [Double] = [0.40, 0.75, 1.00, 0.75, 0.40]
    private static let speeds:      [Double] = [3.20, 5.10, 6.50, 4.80, 3.70]
    private static let phases:      [Double] = [0.00, 1.20, 2.50, 0.70, 1.90]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    let wave = (sin(t * Self.speeds[i] + Self.phases[i]) * 0.5) + 0.5
                    let h    = 4.0 + Double(level) * 16.0 * Self.multipliers[i] * (0.55 + wave * 0.45)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(level > 0.02 ? color : Color.secondary.opacity(0.35))
                        .frame(width: 3, height: max(4, h))
                        .animation(.easeOut(duration: 0.05), value: level)
                }
            }
        }
        .frame(width: 27, height: 24)
    }
}
