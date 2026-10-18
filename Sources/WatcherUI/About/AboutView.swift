import AppKit
import SwiftUI
import WatcherCore

/// Watcher ▸ About Watcher: what this build is, who makes it and how to support it, where its files live, and the
/// open-source work it stands on.
public struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(RequestActions.self) private var actions
    @Environment(DevicesViewModel.self) private var devices
    @Environment(ExternalApps.self) private var externalApps
    public init() {}

    static let libraries: [(name: String, use: String)] = [
        ("SwiftNIO · swift-nio-ssl · swift-nio-http2", "Proxy, TLS and HTTP/2"),
        ("AsyncHTTPClient", "Upstream requests"),
        ("swift-certificates · swift-crypto", "Root CA and per-host certificates"),
        ("SwiftTreeSitter · tree-sitter grammars", "Syntax colouring of large bodies"),
        ("swift-argument-parser", "watcher-cli"),
    ]

    public var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                WatcherLogo(size: 96)
                Text("Watcher").font(.system(size: 26, weight: .bold))
                Text("HTTP(S) debugging proxy for macOS").foregroundStyle(.secondary)
                Text(model.appInfo.versionText)
                    .font(.callout.monospacedDigit()).foregroundStyle(.secondary).textSelection(.enabled)
                HStack(spacing: 4) {
                    Text("by").foregroundStyle(.secondary)
                    Link(ProjectLinks.authorName, destination: ProjectLinks.author)
                        .help(ProjectLinks.author.absoluteString)
                }
                .font(.callout)
                HStack(spacing: 8) {
                    Link(destination: ProjectLinks.repository) {
                        Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                    }
                    .help("Source code, releases and discussions")
                    Link(destination: ProjectLinks.sponsor) {
                        Label("Sponsor", systemImage: "heart.fill").foregroundStyle(.pink)
                    }
                    .help("Watcher is free and open source; sponsoring keeps it going")
                    Link(destination: ProjectLinks.issues) {
                        Label("Report an Issue", systemImage: "exclamationmark.bubble")
                    }
                    .help("Bug reports and feature requests")
                }
                .buttonStyle(.bordered).controlSize(.small).padding(.top, 4)
            }
            .padding(.top, 28).padding(.bottom, 18)

            VStack(spacing: 10) {
                Card("Files", symbol: "folder") {
                    fileRow("Settings, mocks, workspaces", url: model.supportDirectory)
                    fileRow("Root certificate", url: devices.certificateURL)
                }
                Card("Built with", symbol: "shippingbox") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 5) {
                        ForEach(Self.libraries, id: \.name) { library in
                            GridRow {
                                Text(library.name).font(.callout)
                                Text(library.use).font(.callout).foregroundStyle(.secondary)
                            }
                        }
                    }
                    // Only a packaged app carries the notices (tools/build-app.sh writes them).
                    if let notices = ProjectLinks.thirdPartyNotices {
                        Button("Licences and Notices…") { Task { await externalApps.open(notices, with: nil) } }
                            .buttonStyle(.link).font(.callout).padding(.top, 4)
                            .help("The licences of the open-source packages Watcher includes")
                    }
                }
            }
            .padding(.horizontal, 20)

            HStack {
                Text("MIT License · © 2026 \(ProjectLinks.authorName)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Copy Version Info", systemImage: "doc.on.doc") {
                    actions.copy(model.appInfo.diagnostics, "Version info copied")
                }
                .help("Version, build and macOS version, for bug reports")
            }
            .padding(20)
        }
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fileRow(_ title: String, url: URL) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout)
                Text(model.appInfo.abbreviatingHome(url.path)).font(.caption.monospaced()).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            }
            Spacer()
            IconButton("Show in Finder", symbol: "magnifyingglass") { externalApps.reveal(url) }
        }
    }
}
