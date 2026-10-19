import SwiftUI
import WatcherCore

/// The inspector: what the selected request was and the facts about it, then the request and response together.
struct FlowDetailView: View {
    @Environment(WindowRouter.self) private var router
    @Environment(FlowListViewModel.self) private var list

    /// Below this width request and response no longer fit side by side and share the space instead.
    static let sideBySideWidth: CGFloat = 760

    var body: some View {
        if let flow = list.selectedFlow {
            VStack(alignment: .leading, spacing: 0) {
                InspectorHeader(flow: flow)
                    .padding(.horizontal, Metrics.gutter).padding(.top, 12).padding(.bottom, 10)
                Divider()
                exchange(flow).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            ContentUnavailableView {
                Label("No Request Selected", systemImage: "sidebar.right")
            } description: {
                Text("Pick a row to see what was sent and what came back.\n↑ ↓ move through the list · ⌘F filters · ⌘/ shows every shortcut")
            }
        }
    }

    /// Side by side when the inspector is wide enough, otherwise one at a time with a switch in the panel's title row.
    private func exchange(_ flow: Flow) -> some View {
        GeometryReader { geometry in
            if geometry.size.width >= Self.sideBySideWidth {
                HSplitView {
                    MessagePanel(flow: flow, side: .request).frame(minWidth: 300)
                    MessagePanel(flow: flow, side: .response).frame(minWidth: 300)
                }
            } else {
                MessagePanel(flow: flow, side: router.exchangeSide, switchesSide: true).id(router.exchangeSide)
            }
        }
    }
}

// MARK: Header

/// Method, status and URL with the actions people repeat most, then the facts about the exchange.
private struct InspectorHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.timestamp) private var timestamp
    let flow: Flow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Pill(text: flow.request.method, tint: Palette.method(flow.request.method), monospaced: true)
                statusPill
                if !flow.appliedTools.isEmpty {
                    Pill(text: flow.appliedTools.joined(separator: " · "), tint: Palette.modified)
                        .help("Changed by \(flow.appliedTools.joined(separator: ", "))")
                }
                JWTButton(summary: JWTSummary(flow: flow, now: model.now()))
                Spacer(minLength: 8)
                actions
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    SiteIconView(domain: FlowGrouping.domainName(flow.request.host), size: 13)
                    Text(flow.request.host).font(.callout).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    if flow.request.scheme == "https" {
                        Image(systemName: flow.clientTLS != nil ? "lock.fill" : "lock").font(.caption2)
                            .foregroundStyle(flow.clientTLS != nil ? Palette.done : .secondary)
                            .help(flow.clientTLS.map { "Decrypted by Watcher (\($0))" } ?? "Encrypted; add the host to SSL Proxying to see inside")
                    }
                }
                Text(flow.request.path).font(.system(.title3, design: .monospaced).weight(.medium))
                    .lineLimit(2).truncationMode(.middle).textSelection(.enabled).help(flow.request.url)
            }
            meta
            if let error = flow.error {
                Label(error, systemImage: "exclamationmark.octagon.fill").font(.callout).foregroundStyle(Palette.error)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.error.opacity(0.1), in: RoundedRectangle(cornerRadius: Metrics.controlRadius))
                    .textSelection(.enabled)
            }
        }
    }

    private var statusPill: some View {
        let failed = flow.state == .failed
        return HStack(spacing: 4) {
            if flow.state == .pending {
                ProgressView().controlSize(.mini)
            }
            Pill(
                text: flow.inspectorStatusText, tint: Palette.status(flow.response?.status, failed: failed),
                monospaced: false
            )
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        let commands = model.requestCommands(for: flow)
        return GlassGroup {
            HStack(spacing: 2) {
                IconButton("Repeat", symbol: "arrow.clockwise", shortcut: "⌘R") { commands.perform(.repeatRequest) }
                IconButton("Edit & Repeat", symbol: "square.and.pencil", shortcut: "⌥⌘R") {
                    commands.perform(.editAndRepeat)
                }
                IconButton(
                    commands.starTitle,
                    symbol: "star",
                    shortcut: "⌘D",
                    tint: flow.isStarred ? Palette.starred : nil,
                    isOn: flow.isStarred
                ) { commands.perform(.toggleStar) }
                IconButton("Copy as cURL", symbol: "terminal", shortcut: "⇧⌘C") { commands.perform(.copyCURL) }
                Menu {
                    Button("Copy URL", systemImage: "link") { commands.perform(.copyURL) }
                    Button("Save Response Body…", systemImage: "square.and.arrow.down") {
                        commands.perform(.saveResponseBody)
                    }
                    .disabled(!commands.isEnabled(.saveResponseBody))
                    Divider()
                    Button("Mock This Response", systemImage: "theatermasks") { commands.perform(.mockResponse) }
                        .disabled(!commands.isEnabled(.mockResponse))
                    Button("Set as Compare Base", systemImage: "arrow.left.arrow.right") {
                        commands.perform(.setCompareBase)
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 15, weight: .regular)).frame(width: Metrics.iconButton, height: Metrics.iconButton)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("More: copy URL (⌥⌘C), mock (⌥⌘M), compare base (⇧⌘B)").accessibilityLabel("More actions")
            }
        }
    }

    /// Sizes, time and where it came from. Wraps onto a second line in a narrow inspector instead of cutting facts off.
    private var meta: some View {
        let meta = InspectorMeta(flow, timestamp: timestamp)
        return WrappingHStack(spacing: 12, lineSpacing: 6) {
            ForEach(meta.items, id: \.symbol) { item in
                MetaItem(symbol: item.symbol, text: item.text, help: item.help)
            }
            if let app = flow.request.clientApp {
                HStack(spacing: 4) {
                    AppIconView(
                        name: app, kind: flow.request.clientKind, bundlePath: flow.request.clientBundlePath, size: 13
                    )
                    Text(IconStore.displayName(app, kind: flow.request.clientKind)).lineLimit(1)
                }
                .font(.caption).foregroundStyle(.secondary).help("Sent by \(app)")
            }
            if let comment = meta.comment {
                MetaItem(symbol: comment.symbol, text: comment.text, help: comment.help)
            }
        }
    }
}

private struct MetaItem: View {
    let symbol: String, text: String, help: String
    var body: some View {
        Label(text, systemImage: symbol).font(.caption.monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            .help(help).accessibilityLabel("\(help): \(text)")
    }
}
