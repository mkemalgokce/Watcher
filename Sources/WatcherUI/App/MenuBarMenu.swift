import SwiftUI

/// The menu bar item: the proxy switches without bringing the main window forward.
public struct MenuBarMenu: View {
    @Environment(AppModel.self) private var model
    @Environment(ProxyController.self) private var proxy
    @Environment(\.openWindow) private var openWindow
    public init() {}

    public var body: some View {
        Text(verbatim: model.statusLine)
        Button(proxy.isRunning ? "Pause Recording" : "Record") { proxy.toggleRunning() }
            .disabled(proxy.isSwitchingProxy)
        Toggle("System Proxy", isOn: proxy.systemProxyBinding)
            .disabled(!proxy.canSwitchSystemProxy)
        Divider()
        Button("Show Watcher") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit Watcher") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

/// The menu bar item's icon: Watcher's lens, with a dot while the proxy listens.
public struct MenuBarLabel: View {
    @Environment(ProxyController.self) private var proxy
    public init() {}

    public var body: some View {
        Image(nsImage: WatcherAppIcon.menuBar(running: proxy.isRunning))
            .accessibilityLabel(proxy.isRunning ? "Watcher, proxy running" : "Watcher, proxy stopped")
    }
}
