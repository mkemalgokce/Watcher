import AppKit

/// A SwiftPM executable is not a bundled app, so it must ask to be a regular, focusable app.
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        // A packaged Watcher.app shows its own icon; an unbundled run (Xcode, swift run) would show a generic one.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil, let icon = WatcherAppIcon.image {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Watcher keeps capturing from the menu bar after its window closes, like other proxies; the Dock icon brings the window back.
    public func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
