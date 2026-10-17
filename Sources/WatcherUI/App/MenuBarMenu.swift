import SwiftUI

/// The menu bar item: the proxy switches without bringing the main window forward.
public struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    public init() {}

    public var body: some View {
        Text(verbatim: model.statusLine)
        Button(model.isRunning ? "Pause Recording" : "Record") { model.toggleRunning() }
            .disabled(model.isSwitchingProxy)
        Toggle("System Proxy", isOn: Binding(get: { model.systemProxyOn }, set: model.setSystemProxy)).disabled(!model.isRunning)
        Divider()
        Button("Show Watcher") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Watcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// The menu bar item's icon: Watcher's lens, with a dot while the proxy listens.
public struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model
    public init() {}

    public var body: some View {
        Image(nsImage: WatcherAppIcon.menuBar(running: model.isRunning)).accessibilityLabel(model.isRunning ? "Watcher, proxy running" : "Watcher, proxy stopped")
    }
}
