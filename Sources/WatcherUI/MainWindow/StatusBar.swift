import SwiftUI
import WatcherCore

/// The bottom bar: what Watcher is doing right now, each item clickable for the obvious action.
struct StatusBar: View {
    @Environment(AppModel.self) private var model
    @State private var showLegend = false

    /// Tools that change traffic right now, by name.
    private var activeTools: [String] {
        let s = model.settings
        var names: [String] = []
        if !s.mapLocal.active.isEmpty {
            names.append("Map Local")
        }
        if !s.mapRemote.active.isEmpty {
            names.append("Map Remote")
        }
        if !s.blockList.active.isEmpty {
            names.append("Block List")
        }
        if !s.allowList.active.isEmpty {
            names.append("Allow List")
        }
        if !s.breakpoints.active.isEmpty {
            names.append("Breakpoints")
        }
        if !s.scripting.active.isEmpty {
            names.append("Scripting")
        }
        if !s.dnsSpoofing.active.isEmpty {
            names.append("DNS Spoofing")
        }
        if !s.reverseProxy.active.isEmpty {
            names.append("Reverse Proxy")
        }
        if s.throttle.isEnabled {
            names.append("Throttling")
        }
        if s.externalProxy.isEnabled {
            names.append("External Proxy")
        }
        if s.noCaching {
            names.append("No Caching")
        }
        return names
    }

    private var stateTint: Color {
        if model.proxyError != nil {
            return Palette.error
        }
        if model.isSwitchingProxy {
            return Palette.warning
        }
        return model.isRunning ? Palette.done : .secondary
    }

    var body: some View {
        HStack(spacing: 4) {
            // What the proxy is doing, as information only: Record and Pause are in the toolbar.
            HStack(spacing: 6) {
                Circle().fill(stateTint).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(model.statusLine).lineLimit(1).monospacedDigit()
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
            separator
            if model.isRunning, model.settings.listenOnAllInterfaces, let lan = model.lanProxyAddress {
                item(symbol: "iphone", tint: .secondary, text: lan, help: "Address for phones and tablets on this network. Click to copy.") { model.copy(lan, "Device address copied") }
                separator
            }
            item(
                symbol: "network",
                tint: model.systemProxyOn ? Palette.done : .secondary,
                text: model.systemProxyOn ? "System proxy on" : "System proxy off",
                help: model.systemProxyOn ? "Mac traffic goes through Watcher. Click to turn off (⇧⌘Y)." : "Only apps set to use Watcher are captured. Click to capture the whole Mac (⇧⌘Y)."
            ) {
                if model.isRunning {
                    model.setSystemProxy(!model.systemProxyOn)
                } else {
                    model.notices.notify("Start the proxy first.", .error)
                }
            }
            let decryptsAll = model.settings.sslProxying.include.contains("*") && model.settings.sslProxying.exclude.isEmpty
            item(
                symbol: "lock.open.fill",
                tint: decryptsAll ? Palette.done : .secondary,
                text: decryptsAll ? "HTTPS decrypted" : "HTTPS: \(model.settings.sslProxying.include.count) hosts",
                help: "Which HTTPS hosts Watcher decrypts (SSL Proxying in Tools). Apps must trust the Watcher certificate."
            ) { model.toolsSelection = .sslProxying; model.show(.tools) }
            if !activeTools.isEmpty {
                item(
                    symbol: "wrench.adjustable.fill",
                    tint: Palette.modified,
                    text: activeTools.count == 1 ? activeTools[0] : "\(activeTools.count) tools on",
                    help: "Changing traffic: \(activeTools.joined(separator: ", ")). Click to open Tools (⌘T)."
                ) { model.show(.tools) }
            }
            if !model.hits.isEmpty {
                item(
                    symbol: "pause.circle.fill",
                    tint: Palette.paused,
                    text: "\(model.hits.count) paused",
                    help: "Requests waiting at a breakpoint. Click to review (⌘B)."
                ) { model.show(.breakpoints) }
            }
            Spacer(minLength: 8)
            if let busy = model.sessionFiles.busyMessage {
                HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(busy).lineLimit(1) }.accessibilityElement(children: .combine)
            }
            Text(summary).foregroundStyle(.secondary).lineLimit(1).help("Requests shown with the current filters, and their response sizes")
            Button("Legend", systemImage: "info.circle") { showLegend.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("What the colours and symbols mean")
                .popover(isPresented: $showLegend, arrowEdge: .top) { ScrollView { Legend().padding(14) }.frame(width: 420, height: 460) }
        }
        .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var summary: String {
        "\(model.visibleFlows.count) of \(model.flows.count) · \(Format.bytes(model.visibleBytes))"
    }

    private var separator: some View {
        Divider().frame(height: 12).padding(.horizontal, 2)
    }

    private func item(symbol: String, tint: Color, text: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: symbol).foregroundStyle(tint).imageScale(.small)
                Text(text).foregroundStyle(.primary)
            }
            .padding(.horizontal, 6).padding(.vertical, 2).contentShape(Rectangle())
        }
        .buttonStyle(.borderless).help(help).accessibilityLabel(text).accessibilityHint(help)
    }
}
