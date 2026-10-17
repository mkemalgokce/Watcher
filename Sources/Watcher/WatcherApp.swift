import AppKit
import SwiftUI
import WatcherUI

@main
struct WatcherApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var model = AppModel()

    var body: some Scene {
        // One main window: there is one session, so a second window would only show the same list again.
        // Unlike WindowGroup it always opens at launch and can be brought back from the Window menu.
        Window("Watcher", id: "main") {
            ContentView().environment(model).frame(minWidth: 1040, minHeight: 560)
        }
        .defaultSize(width: 1320, height: 780)
        .commands {
            WatcherCommands(model: model)
        }

        Window("Compare", id: "compare") { CompareWindow().environment(model) }
            .defaultSize(width: 900, height: 640)

        Window("About Watcher", id: "about") { AboutView().environment(model) }
            .windowResizability(.contentSize)
            .windowStyle(.hiddenTitleBar)

        Settings { SettingsView().environment(model) }

        // No isInserted binding: the status item writes it back on every update, which loops through UserDefaults and freezes the app.
        // People hide it from System Settings ▸ Menu Bar instead.
        MenuBarExtra { MenuBarMenu().environment(model) } label: { MenuBarLabel().environment(model) }
    }
}

/// A SwiftPM executable is not a bundled app, so it must ask to be a regular, focusable app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.regular)
        // A packaged Watcher.app shows its own icon; an unbundled run (Xcode, swift run) would show a generic one.
        if Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") == nil, let icon = WatcherAppIcon.image {
            NSApp.applicationIconImage = icon
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Watcher keeps capturing from the menu bar after its window closes, like other proxies; the Dock icon brings the window back.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }
}
