import WatcherCore

/// What the bottom bar shows and what each item does when clicked. It holds no state of its own: every value is read
/// from the models it was built from, so a view that reads it redraws when they change.
@MainActor
struct StatusBarViewModel {
    enum Tone: Equatable {
        case error, warning, done, neutral
    }

    let proxy: ProxyController
    let settings: SettingsEditor
    let devices: DevicesViewModel
    let breakpoints: BreakpointsViewModel
    let list: FlowListViewModel
    let sessionFiles: SessionFilesViewModel
    let notices: NoticeCenter
    let actions: RequestActions
    let router: WindowRouter
    let statusLine: () -> String

    var line: String {
        statusLine()
    }

    var stateTone: Tone {
        switch proxy.state {
        case .failed: .error
        case .switching: .warning
        case .running: .done
        case .stopped: .neutral
        }
    }

    /// For phones and tablets on this network; only while the proxy listens beyond this Mac.
    var lanAddress: String? {
        proxy.isRunning && settings.listenOnAllInterfaces ? devices.lanProxyAddress : nil
    }

    var systemProxyTone: Tone {
        proxy.systemProxyOn ? .done : .neutral
    }

    var systemProxyText: String {
        proxy.systemProxyOn ? "System proxy on" : "System proxy off"
    }

    var systemProxyHelp: String {
        proxy.systemProxyOn
            ? "Mac traffic goes through Watcher. Click to turn off (⇧⌘Y)."
            : "Only apps set to use Watcher are captured. Click to capture the whole Mac (⇧⌘Y)."
    }

    var https: StatusBarText.HTTPS {
        StatusBarText.https(settings.sslProxying)
    }

    var activeTools: [String] {
        ToolPage.activeNames(in: settings.value)
    }

    var toolsText: String {
        StatusBarText.tools(activeTools)
    }

    var toolsHelp: String {
        "Changing traffic: \(activeTools.joined(separator: ", ")). Click to open Tools (⌘T)."
    }

    var pausedCount: Int {
        breakpoints.hits.count
    }

    var pausedText: String {
        "\(pausedCount) paused"
    }

    var busyMessage: String? {
        sessionFiles.busyMessage
    }

    var summary: String {
        "\(list.visibleFlows.count) of \(list.flows.count) · \(Format.bytes(list.visibleBytes))"
    }

    func copyLanAddress() {
        guard let lanAddress else { return }
        actions.copy(lanAddress, "Device address copied")
    }

    func toggleSystemProxy() {
        guard proxy.isRunning else { return notices.notify("Start the proxy first.", .error) }
        proxy.toggleSystemProxy()
    }

    func showSSLProxying() {
        router.toolsSelection = .sslProxying
        router.show(.tools)
    }

    func showTools() {
        router.show(.tools)
    }

    func showBreakpoints() {
        router.show(.breakpoints)
    }
}
