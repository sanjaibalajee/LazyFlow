import AppKit
import CoreGraphics

enum ScreenshotService {
    /// Captures the frontmost app's top window. Returns base64-encoded JPEG, or nil
    /// if Screen Recording permission is not granted or capture fails.
    static func captureFrontmost() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        // Find the topmost normal-layer window belonging to the frontmost app
        let appWindows = windowList.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == app.processIdentifier &&
            ($0[kCGWindowLayer as String] as? Int32 ?? 999) == 0
        }
        guard let topWindow = appWindows.first,
              let windowID  = topWindow[kCGWindowNumber as String] as? CGWindowID else { return nil }

        guard let cgImage = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            windowID,
            [.boundsIgnoreFraming, .nominalResolution]
        ) else { return nil }

        var nsImage = NSImage(cgImage: cgImage, size: .zero)

        // Downscale to max 900px wide — keeps token count under ~5k tokens per image
        let maxWidth: CGFloat = 900
        if nsImage.size.width > maxWidth {
            let scale   = maxWidth / nsImage.size.width
            let newSize = NSSize(width: maxWidth, height: nsImage.size.height * scale)
            let scaled  = NSImage(size: newSize)
            scaled.lockFocus()
            nsImage.draw(in: NSRect(origin: .zero, size: newSize),
                         from: NSRect(origin: .zero, size: nsImage.size),
                         operation: .sourceOver, fraction: 1.0)
            scaled.unlockFocus()
            nsImage = scaled
        }

        guard let tiff   = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              // 35% quality — sufficient for the model to read text/UI, ~3-6k tokens
              let jpeg   = bitmap.representation(
                  using: .jpeg,
                  properties: [.compressionFactor: NSNumber(value: 0.35)]
              ) else { return nil }

        return jpeg.base64EncodedString()
    }
}
