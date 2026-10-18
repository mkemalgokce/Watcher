import AppKit

/// Watcher's own icon, so the Dock shows it even when the app runs unbundled from Xcode or `swift run`.
public enum WatcherAppIcon {
    @MainActor public static var image: NSImage? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }

    /// The menu bar glyph: a dot in the lens while the proxy listens. A template image, so macOS colours it for light, dark and tinted bars.
    @MainActor public static func menuBar(running: Bool) -> NSImage {
        // Inline rather than a resource: the packaged app does not carry SwiftPM's resource bundle, and Bundle.module would trap there.
        let dot = running ? ##"<circle cx="22" cy="18" r="2.3" fill="#000"/>"## : ""
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 36" fill="none" stroke="#000" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="22" cy="18" r="7.5"/><path d="M4 14 H11.5 M32.5 14 H40 M36.5 10.5 L40 14 L36.5 17.5"/><path d="M40 22 H32.5 M11.5 22 H4 M7.5 18.5 L4 22 L7.5 25.5"/>"## + dot + "</svg>"
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.size = NSSize(width: 22, height: 18)
        image.isTemplate = true
        return image
    }
}
