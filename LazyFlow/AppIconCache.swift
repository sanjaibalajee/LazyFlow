import SwiftUI
import AppKit

// Resolving an app icon means a `NSWorkspace.urlForApplication` lookup plus a filesystem
// read for the icon itself. Rows are recycled and re-rendered constantly, so the result is
// cached process-wide keyed by bundle ID — the cost is paid once per distinct app, not once
// per row instance.
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static let placeholder: NSImage =
        NSImage(systemSymbolName: "app.dashed", accessibilityDescription: nil) ?? NSImage()

    static func icon(for bundleIdentifier: String?) -> NSImage {
        guard let id = bundleIdentifier, !id.isEmpty else { return placeholder }
        if let hit = cache[id] { return hit }
        let resolved = resolve(id)
        cache[id] = resolved
        return resolved
    }

    private static func resolve(_ bundleIdentifier: String) -> NSImage {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
           let icon = running.icon {
            return icon
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return placeholder
    }
}

// MARK: - View

/// Square app icon for a bundle ID. Backed by `AppIconCache`, so it is safe to use inside
/// long lists without hitting the filesystem on every render.
struct AppIcon: View {
    let bundleIdentifier: String?
    var cornerRadius: CGFloat = 6

    var body: some View {
        Image(nsImage: AppIconCache.icon(for: bundleIdentifier))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
