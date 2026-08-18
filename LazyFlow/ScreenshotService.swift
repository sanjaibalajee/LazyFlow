import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenshotService {
    /// Captures the frontmost app's top window. Returns base64-encoded JPEG, or nil
    /// if Screen Recording permission is not granted or capture fails.
    static func captureFrontmost() async -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            guard let window = content.windows.first(where: {
                $0.owningApplication?.processID == app.processIdentifier &&
                $0.windowLayer == 0 &&
                $0.frame.width > 1 && $0.frame.height > 1
            }) else { return nil }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let configuration = SCStreamConfiguration()

            // Capture directly at model-friendly resolution instead of allocating a full-size
            // image and redrawing it through AppKit.
            let scale = NSScreen.screens
                .first(where: { $0.frame.intersects(window.frame) })?
                .backingScaleFactor ?? 2
            let naturalWidth = max(window.frame.width * scale, 1)
            let outputWidth = min(naturalWidth, 900)
            configuration.width = Int(outputWidth.rounded())
            configuration.height = max(
                Int((window.frame.height * outputWidth / window.frame.width).rounded()),
                1
            )
            configuration.scalesToFit = true
            configuration.showsCursor = false
            configuration.ignoreShadowsSingleWindow = true

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let jpeg = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: NSNumber(value: 0.35)]
            ) else { return nil }

            return jpeg.base64EncodedString()
        } catch {
            print("[LazyFlow] Screenshot capture failed: \(error.localizedDescription)")
            return nil
        }
    }
}
