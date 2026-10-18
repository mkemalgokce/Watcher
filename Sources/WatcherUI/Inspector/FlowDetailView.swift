import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

/// The inspector: what the selected request was and the facts about it, then the request and response together.
struct FlowDetailView: View {
    @Environment(AppModel.self) private var model

    /// Below this width request and response no longer fit side by side and share the space instead.
    static let sideBySideWidth: CGFloat = 760

    var body: some View {
        if let flow = model.selectedFlow {
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
                MessagePanel(flow: flow, side: model.exchangeSide, switchesSide: true).id(model.exchangeSide)
            }
        }
    }
}

// MARK: Header

/// Method, status and URL with the actions people repeat most, then the facts about the exchange.
private struct InspectorHeader: View {
    @Environment(AppModel.self) private var model
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
                JWTButton(flow: flow)
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
        let text: String = switch flow.state {
        case .pending: "Pending"
        case .failed: "Failed"
        case .blocked, .completed: flow.response.map { "\($0.status) \(HTTPStatus.reason($0.status))" } ?? "—"
        }
        return HStack(spacing: 4) {
            if flow.state == .pending {
                ProgressView().controlSize(.mini)
            }
            Pill(text: text, tint: Palette.status(flow.response?.status, failed: failed), monospaced: false)
        }
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        GlassGroup {
            HStack(spacing: 2) {
                IconButton("Repeat", symbol: "arrow.clockwise", shortcut: "⌘R") { model.repeatRequest(flow.request) }
                IconButton("Edit & Repeat", symbol: "square.and.pencil", shortcut: "⌥⌘R") { model.editAndRepeat(flow) }
                IconButton(
                    flow.isStarred ? "Remove Star" : "Star",
                    symbol: "star",
                    shortcut: "⌘D",
                    tint: flow.isStarred ? Palette.starred : nil,
                    isOn: flow.isStarred
                ) { model.toggleStar([flow.id]) }
                IconButton("Copy as cURL", symbol: "terminal", shortcut: "⇧⌘C") { model.copy(model.code(for: flow.request, as: .curl), "cURL copied") }
                Menu {
                    Button("Copy URL", systemImage: "link") { model.copy(flow.request.url, "URL copied") }
                    Button("Save Response Body…", systemImage: "square.and.arrow.down") {
                        let name = ExchangeText.suggestedFileName(for: flow, side: .response)
                        model.saveData(ExchangeText.body(of: flow, side: .response), suggestedName: name)
                    }
                    .disabled(flow.response?.body.isEmpty ?? true)
                    Divider()
                    Button("Mock This Response", systemImage: "theatermasks") { model.mockResponse(flow) }.disabled(flow.response == nil)
                    Button("Set as Compare Base", systemImage: "arrow.left.arrow.right") { model.compare(withBase: flow) }
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
        let timing = TimingBreakdown(flow)
        return WrappingHStack(spacing: 12, lineSpacing: 6) {
            if timing.isComplete {
                MetaItem(symbol: "clock", text: Format.duration(timing.total), help: "Total time. \(timing.verdict)")
                if flow.timeToFirstByte != nil {
                    MetaItem(symbol: "hourglass", text: "TTFB \(Format.duration(timing.phases[0].seconds))", help: "Waiting for the server: from sending the request to the first byte back")
                    MetaItem(symbol: "arrow.down.to.line", text: Format.duration(timing.phases[1].seconds), help: "Downloading the rest of the response")
                }
            } else if flow.state == .pending {
                MetaItem(symbol: "clock", text: "Waiting…", help: "The response has not finished yet")
            }
            if !flow.request.body.isEmpty {
                MetaItem(symbol: "arrow.up.circle", text: Format.bytes(flow.request.body.count), help: "Request body size")
            }
            if let response = flow.response {
                MetaItem(symbol: "arrow.down.circle", text: Format.bytes(response.body.count), help: "Response body size")
            }
            if let version = flow.upstreamHTTPVersion {
                MetaItem(symbol: "network", text: version, help: "Protocol used with the server")
            }
            if let tls = flow.clientTLS {
                MetaItem(symbol: "lock.fill", text: tls, help: "TLS between the app and Watcher")
            }
            MetaItem(symbol: "calendar.badge.clock", text: flow.startedAt.formatted(date: .omitted, time: .standard), help: "Started \(flow.startedAt.formatted(date: .abbreviated, time: .standard))")
            if let app = flow.request.clientApp {
                HStack(spacing: 4) { AppIconView(process: app, size: 13); Text(IconStore.appName(forProcess: app)).lineLimit(1) }
                    .font(.caption).foregroundStyle(.secondary).help("Sent by \(app)")
            }
            if let comment = flow.comment {
                MetaItem(symbol: "text.bubble", text: comment, help: "Your comment")
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
