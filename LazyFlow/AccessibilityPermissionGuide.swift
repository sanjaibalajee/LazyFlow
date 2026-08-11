import AppKit
import SwiftUI

/// A small floating helper that stays visible while System Settings is frontmost.
/// The app icon is backed by the running `.app` bundle URL, so dragging it is the
/// same operation as dragging LazyFlow from Finder.
@MainActor
final class AccessibilityPermissionGuideController: NSWindowController, NSWindowDelegate {
    private let onClose: () -> Void

    init(onOpenSettings: @escaping () -> Void, onRevealInFinder: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.onClose = onClose

        let rootView = AccessibilityPermissionGuide(
            onOpenSettings: onOpenSettings,
            onRevealInFinder: onRevealInFinder
        )
        let hostingController = NSHostingController(rootView: rootView)
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 410, height: 470),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Add LazyFlow to Accessibility"
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentViewController = hostingController

        super.init(window: panel)
        panel.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present() {
        guard let window else { return }
        window.center()
        showWindow(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private struct AccessibilityPermissionGuide: View {
    let onOpenSettings: () -> Void
    let onRevealInFinder: () -> Void

    private var appIcon: NSImage {
        NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path)
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 7) {
                Text("Add LazyFlow to Accessibility")
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                Text("This lets the global shortcut insert your finished dictation at the cursor.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.28), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(21)
                    AppBundleDragSource(bundleURL: Bundle.main.bundleURL, dragImage: appIcon)
                }
                .frame(width: 126, height: 126)
                .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
                .help("Drag LazyFlow into the Accessibility apps list")

                Label("Drag this icon into the Accessibility list", systemImage: "cursorarrow.motionlines")
                    .font(.system(size: 13, weight: .semibold))
            }

            VStack(alignment: .leading, spacing: 8) {
                instruction(1, "Open Accessibility Settings below.")
                instruction(2, "If LazyFlow is missing, drag the icon above into the app list.")
                instruction(3, "Turn LazyFlow on. macOS may ask you to relaunch it.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 13, style: .continuous))

            HStack(spacing: 10) {
                Button("Reveal in Finder", action: onRevealInFinder)
                    .buttonStyle(.bordered)
                Button("Open Accessibility Settings", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }

            Text("LazyFlow never receives this permission automatically—you stay in control of the final toggle.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 28)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(width: 410, height: 470)
        .background(.ultraThinMaterial)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Color.accentColor, in: Circle())
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AppBundleDragSource: NSViewRepresentable {
    let bundleURL: URL
    let dragImage: NSImage

    func makeNSView(context: Context) -> BundleDragView {
        BundleDragView(bundleURL: bundleURL, dragImage: dragImage)
    }

    func updateNSView(_ nsView: BundleDragView, context: Context) {
        nsView.bundleURL = bundleURL
        nsView.dragImage = dragImage
    }
}

@MainActor
private final class BundleDragView: NSView, NSDraggingSource {
    var bundleURL: URL
    var dragImage: NSImage
    private var initialEvent: NSEvent?

    init(bundleURL: URL, dragImage: NSImage) {
        self.bundleURL = bundleURL
        self.dragImage = dragImage
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Drag LazyFlow into Accessibility settings")
        setAccessibilityHelp("Drag this app icon into the list in System Settings")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        initialEvent = event
    }

    override func mouseDragged(with event: NSEvent) {
        guard initialEvent != nil else { return }
        initialEvent = nil

        let item = NSDraggingItem(pasteboardWriter: bundleURL as NSURL)
        let imageSize = NSSize(width: 82, height: 82)
        let point = convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(
            NSRect(
                x: point.x - imageSize.width / 2,
                y: point.y - imageSize.height / 2,
                width: imageSize.width,
                height: imageSize.height
            ),
            contents: dragImage
        )

        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func mouseUp(with event: NSEvent) {
        initialEvent = nil
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
        true
    }
}
