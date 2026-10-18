import SwiftUI
import WatcherCore

struct FlowListView: View {
    @Environment(AppModel.self) private var model
    @Environment(FlowListViewModel.self) private var list
    @Environment(RequestActions.self) private var actions
    @State private var commenting: Flow?
    @State private var commentText = ""
    /// Which columns are shown and in what order; right-click a column header to change it.
    @SceneStorage("flowList.columns") private var columns = TableColumnCustomization<Flow>()

    var body: some View {
        @Bindable var model = model
        let flows = list.visibleFlows
        // Bars in the Duration column are relative to the slowest request on screen.
        let slowest = flows.lazy.compactMap(\.duration).max() ?? 0
        Table(flows, selection: Bindable(list).selection, sortOrder: Bindable(list).sortOrder, columnCustomization: $columns) {
            TableColumn("#", value: \.sequence) { Text("\($0.sequence)").monospacedDigit().foregroundStyle(.secondary) }
                .width(min: 22, ideal: 30).customizationID("sequence")
            TableColumn("Date", value: \.startedAt) { flow in
                Text(flow.startedAt.formatted(.dateTime.hour().minute().second())).monospacedDigit().foregroundStyle(.secondary)
                    .help(flow.startedAt.formatted(date: .complete, time: .standard))
            }
            .width(min: 54, ideal: 60).customizationID("date")
            TableColumn("Method", value: \.request.method) { MethodBadge(method: $0.request.method) }
                .width(min: 40, ideal: 48).customizationID("method")
            TableColumn("Status", value: \.sortStatus) { StatusPill(flow: $0) }
                .width(min: 44, ideal: 54).customizationID("status")
            TableColumn("Request", value: \.sortURL) { RequestCell(flow: $0) }
                .width(min: 120, ideal: 160).customizationID("request").disabledCustomizationBehavior(.visibility)
            TableColumn("App", value: \.sortApp) { flow in
                if let app = flow.request.clientApp {
                    HStack(spacing: 5) { AppIconView(process: app, size: 14); Text(IconStore.appName(forProcess: app)).lineLimit(1).foregroundStyle(.secondary) }
                        .help(app).accessibilityElement(children: .combine)
                }
            }.width(min: 40, ideal: 80).customizationID("app")
                // The app is also in the sidebar and the inspector; hidden at first so the list fits a narrow window. Right-click a header to show it.
                .defaultVisibility(.hidden)
            TableColumn("Size", value: \.sortSize) { flow in
                Text(flow.response.map { Format.bytes($0.body.count) } ?? "").monospacedDigit().foregroundStyle(.secondary)
            }.width(min: 40, ideal: 48).alignment(.trailing).customizationID("size")
            TableColumn("Duration", value: \.sortDuration) { TimeCell(flow: $0, slowest: slowest) }
                .width(min: 56, ideal: 80).customizationID("time")
        }
        .contextMenu(forSelectionType: Flow.ID.self) { ids in
            FlowActions(ids: ids, onComment: { flow in commentText = flow.comment ?? ""; commenting = flow })
        } primaryAction: { ids in
            if let flow = list.flows.first(where: { ids.contains($0.id) }) {
                actions.editAndRepeat(flow)
            }
        }
        // Plain rows like Mail: striping the empty space below a short list only adds noise.
        .alternatingRowBackgrounds(.disabled)
        .onDeleteCommand { actions.delete(list.selection.map { [$0] } ?? []) }
        .safeAreaInset(edge: .top, spacing: 0) { FilterSummary() }
        .overlay {
            if flows.isEmpty {
                if list.flows.isEmpty {
                    GettingStarted()
                } else {
                    NoMatches()
                }
            }
        }
        .alert("Comment", isPresented: Binding(get: { commenting != nil }, set: {
            if !$0 {
                commenting = nil
            }
        })) {
            TextField("Comment", text: $commentText)
            Button("Save") {
                if let commenting {
                    actions.setComment(commentText, for: commenting.id)
                }; commenting = nil
            }
            Button("Cancel", role: .cancel) { commenting = nil }
        }
    }
}

/// Host and path in one column, so the part people scan for (the path) is never the column that gets cut off.
private struct RequestCell: View {
    let flow: Flow

    var body: some View {
        let https = flow.request.scheme == "https"
        HStack(spacing: 5) {
            if flow.isStarred {
                Image(systemName: "star.fill").font(.caption2).foregroundStyle(Palette.starred).accessibilityHidden(true)
            }
            SiteIconView(domain: FlowGrouping.domainName(flow.request.host), size: 14)
            if https {
                Image(systemName: flow.clientTLS != nil ? "lock.fill" : "lock").font(.caption2).foregroundStyle(.secondary).accessibilityHidden(true)
            }
            // The path is what people scan for, so the host gives way first when the column is narrow.
            HStack(spacing: 0) {
                Text(flow.request.host).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head).layoutPriority(0)
                Text(flow.request.path).lineLimit(1).truncationMode(.middle).layoutPriority(1)
            }
            Spacer(minLength: 0)
            ContentKindIcon(kind: FlowFilter.kind(of: flow))
            if let comment = flow.comment {
                Image(systemName: "text.bubble").font(.caption2).foregroundStyle(.secondary).help(comment).accessibilityHidden(true)
            }
        }
        .help(flow.request.url)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText(https: https))
    }

    private func accessibilityText(https: Bool) -> String {
        var parts = [flow.request.host + flow.request.path]
        if https {
            parts.append(flow.clientTLS != nil ? "HTTPS, decrypted" : "HTTPS, not decrypted")
        }
        if flow.isStarred {
            parts.append("starred")
        }
        if let comment = flow.comment {
            parts.append("comment: \(comment)")
        }
        return parts.joined(separator: ", ")
    }
}

/// Duration as a number and as a bar against the slowest visible request, so slow calls stand out while scrolling.
private struct TimeCell: View {
    let flow: Flow
    let slowest: TimeInterval

    var body: some View {
        if let duration = flow.duration {
            HStack(spacing: 6) {
                Text(Format.duration(duration)).monospacedDigit().foregroundStyle(.secondary).lineLimit(1).fixedSize()
                    .frame(minWidth: 44, alignment: .trailing)
                GeometryReader { geometry in
                    Capsule().fill(.quaternary)
                        .overlay(alignment: .leading) {
                            Capsule().fill(flow.state == .failed ? Palette.error : Color.accentColor.opacity(0.75))
                                .frame(width: max(3, geometry.size.width * (slowest > 0 ? duration / slowest : 0)))
                        }
                }
                .frame(minWidth: 6).frame(height: 4).accessibilityHidden(true)
            }
            .accessibilityElement(children: .combine)
        } else if flow.state == .pending {
            ProgressView().controlSize(.mini).accessibilityLabel("Waiting for the response")
        }
    }
}

/// Requests exist but none pass the search, quick filters or sidebar choice.
private struct NoMatches: View {
    @Environment(FlowListViewModel.self) private var list

    var body: some View {
        ContentUnavailableView {
            Label(list.query.text.isEmpty ? "No matching requests" : "No results for “\(list.query.text)”", systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("\(list.flows.count) requests are hidden by the current filters.")
        } actions: {
            Button("Clear Filters") { list.query.reset(); list.sidebar = .all }
        }
    }
}

/// The empty list on a first run: the three things that have to happen before traffic shows up.
private struct GettingStarted: View {
    @Environment(WindowRouter.self) private var router
    @Environment(ProxyController.self) private var proxy
    @Environment(DevicesViewModel.self) private var devices
    private var port: Int {
        proxy.port
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                WatcherLogo(size: 48)
                Text(proxy.isRunning ? "Waiting for traffic" : "Capture your first request")
                    .font(.title3.weight(.semibold))
            }
            if let error = proxy.proxyError {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Palette.error).font(.callout)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            step(1, done: proxy.isRunning, "Start the proxy", detail: "Watcher listens on 127.0.0.1:\(port).", shortcut: "⇧⌘P") {
                HStack {
                    Button(proxy.proxyError == nil ? "Start Proxy" : "Try Again") { proxy.toggleRunning() }
                        .buttonStyle(.borderedProminent)
                        .disabled(proxy.isRunning || proxy.isSwitchingProxy)
                    if proxy.isSwitchingProxy {
                        ProgressView().controlSize(.small).accessibilityLabel("Starting the proxy")
                    }
                }
            }
            step(2, done: proxy.systemProxyOn, "Send this Mac's traffic through it", detail: "Or set the proxy in one app or on a phone instead.", shortcut: "⇧⌘Y") {
                Button("Turn On System Proxy") { proxy.setSystemProxy(true) }
                    .disabled(!proxy.isRunning || proxy.systemProxyOn)
            }
            step(3, done: devices.macTrusted, "Trust the certificate to read HTTPS", detail: "Without it you still see hosts, but not what is inside HTTPS requests.", shortcut: "⇧⌘D") {
                HStack {
                    Button("Trust on This Mac…") { Task { await devices.trustOnMac() } }.disabled(devices.macTrusted)
                    Button("Phone or Simulator…") { router.show(.devices) }
                }
            }
            // String(port): interpolating the Int straight into Text would format it as "9.090" in some locales.
            Text(LocalizedStringKey("Try it: run `curl -x http://127.0.0.1:\(String(port)) http://example.com` in Terminal."))
                .font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
        }
        .padding(24).frame(maxWidth: 460, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.background)
        .task { await devices.refreshMacTrust() }
    }

    private func step(_ number: Int, done: Bool, _ title: String, detail: String, shortcut: String, @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "\(number).circle").foregroundStyle(done ? Palette.done : Color.secondary)
                .imageScale(.large).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(title).font(.headline)
                    Text(shortcut).font(.caption).foregroundStyle(.secondary)
                }
                Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                action().controlSize(.small)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(number) of 3: \(title)\(done ? ", done" : "")")
    }
}

/// Shown only while something narrows the list: how many requests are left, and one click to see them all again.
/// The filters themselves are tokens in the search field.
private struct FilterSummary: View {
    @Environment(FlowListViewModel.self) private var list

    var body: some View {
        if list.query.isActive || list.sidebar != .all {
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .foregroundStyle(.tint).accessibilityHidden(true)
                Text("\(list.visibleFlows.count) of \(list.flows.count) requests").font(.callout.monospacedDigit())
                Spacer(minLength: 8)
                Button("Clear Filters") {
                    withAnimation(.easeOut(duration: 0.15)) { list.query.reset(); list.sidebar = .all }
                }
                .buttonStyle(.link).help("Show every request (⇧⌘L)")
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}
