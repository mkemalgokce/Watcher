import SwiftUI
import WatcherCore

/// The bottom bar: what Watcher is doing right now, each item clickable for the obvious action.
struct StatusBar: View {
    let viewModel: StatusBarViewModel
    @State private var showLegend = false

    private func tint(_ tone: StatusBarViewModel.Tone) -> Color {
        switch tone {
        case .error: Palette.error
        case .warning: Palette.warning
        case .done: Palette.done
        case .neutral: .secondary
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            // What the proxy is doing, as information only: Record and Pause are in the toolbar.
            HStack(spacing: 6) {
                Circle().fill(tint(viewModel.stateTone)).frame(width: 7, height: 7).accessibilityHidden(true)
                Text(viewModel.line).lineLimit(1).monospacedDigit()
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .combine)
            separator
            if let lan = viewModel.lanAddress {
                item(
                    symbol: "iphone", tint: .secondary, text: lan,
                    help: "Address for phones and tablets on this network. Click to copy."
                ) { viewModel.copyLanAddress() }
                separator
            }
            item(
                symbol: "network",
                tint: tint(viewModel.systemProxyTone),
                text: viewModel.systemProxyText,
                help: viewModel.systemProxyHelp
            ) { viewModel.toggleSystemProxy() }
            let https = viewModel.https
            item(
                symbol: "lock.open.fill",
                tint: tint(https.decryptsAll ? .done : .neutral),
                text: https.text,
                help: "Which HTTPS hosts Watcher decrypts (SSL Proxying in Tools). Apps must trust the Watcher certificate."
            ) { viewModel.showSSLProxying() }
            if !viewModel.activeTools.isEmpty {
                item(
                    symbol: "wrench.adjustable.fill",
                    tint: Palette.modified,
                    text: viewModel.toolsText,
                    help: viewModel.toolsHelp
                ) { viewModel.showTools() }
            }
            if viewModel.pausedCount > 0 {
                item(
                    symbol: "pause.circle.fill",
                    tint: Palette.paused,
                    text: viewModel.pausedText,
                    help: "Requests waiting at a breakpoint. Click to review (⌘B)."
                ) { viewModel.showBreakpoints() }
            }
            Spacer(minLength: 8)
            if let busy = viewModel.busyMessage {
                HStack(spacing: 4) { ProgressView().controlSize(.mini); Text(busy).lineLimit(1) }.accessibilityElement(children: .combine)
            }
            Text(viewModel.summary).foregroundStyle(.secondary).lineLimit(1)
                .help("Requests shown with the current filters, and their response sizes")
            Button("Legend", systemImage: "info.circle") { showLegend.toggle() }
                .labelStyle(.iconOnly).buttonStyle(.borderless).help("What the colours and symbols mean")
                .popover(isPresented: $showLegend, arrowEdge: .top) { ScrollView { Legend().padding(14) }.frame(width: 420, height: 460) }
        }
        .font(.caption).padding(.horizontal, 8).padding(.vertical, 4).background(.bar)
        .overlay(alignment: .top) { Divider() }
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
