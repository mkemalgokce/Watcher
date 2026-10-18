import SwiftUI
import WatcherCore

public struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @State private var workspaceName = ""

    public init() {}

    private var filterTokens: Binding<[FilterToken]> {
        Binding(get: { FilterToken.tokens(in: model.query) }, set: { FilterToken.apply($0, to: &model.query) })
    }

    public var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            SidebarView().navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 320)
        } content: {
            FlowListView().navigationSplitViewColumnWidth(min: 480, ideal: 700)
        } detail: {
            FlowDetailView().navigationSplitViewColumnWidth(min: 380, ideal: 520)
        }
        .navigationTitle("Watcher")
        // Every filter lives in the search field as a token; typing offers where to look and the quick filters it names.
        .searchable(text: $model.query.text, tokens: filterTokens, placement: .toolbar, prompt: "Filter requests") {
            Label($0.title, systemImage: $0.symbol)
        }
        .searchSuggestions {
            let present = FilterToken.tokens(in: model.query)
            let hosts = model.counts.domains.map(\.name)
            ForEach(FilterToken.suggestions(for: model.query.text, hosts: hosts, excluding: present)) {
                Label($0.title, systemImage: $0.symbol).searchCompletion($0)
            }
        }
        .modifier(SearchFocus(request: model.searchFocusRequest))
        .toolbar { WatcherToolbar() }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar() }
        .sheet(item: $model.sheet) { sheet in
            switch sheet {
            case .tools: ToolsView()
            case .breakpoints: BreakpointsView()
            case .compose: ComposeView()
            case .devices: DeviceSetupView()
            case .welcome: WelcomeView()
            case .converter: ConverterView()
            case .help: HelpView()
            }
        }
        .alert("Save Workspace", isPresented: $model.askWorkspaceName) {
            TextField("Name", text: $workspaceName)
            Button("Save") { model.saveWorkspace(named: workspaceName); workspaceName = "" }
            Button("Cancel", role: .cancel) { workspaceName = "" }
        } message: { Text("Saves the current requests and all tool settings.") }
        .overlay(alignment: .bottom) { NoticeBanner().padding(.bottom, 34) } // above the status bar, clear of the filter bar
        .onChange(of: model.compareWindowRequest) { _, _ in openWindow(id: "compare") }
        .task {
            // Nothing is captured until Record is pressed.
            if !model.onboardingDone {
                model.sheet = .welcome
            }
        }
    }
}

/// Record, Compose and Clear on the left, screens on the right; what the proxy is doing is in the status bar.
/// Record starts the proxy and Pause stops it, so capturing has one switch.
private struct WatcherToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model

    /// Native toolbar buttons: macOS draws them as Liquid Glass and groups each ToolbarItemGroup into one capsule, as in Xcode.
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.toggleRunning() } label: {
                Label(
                    model.isRunning ? "Pause" : "Record",
                    systemImage: model.isRunning ? "pause.fill" : "record.circle"
                )
            }
            .disabled(model.isSwitchingProxy)
            .help(model.isRunning ? "Recording. Click to stop the proxy (⌘E)" : "Start the proxy and record (⌘E)")
            Button { model.show(.compose) } label: { Label("Compose", systemImage: "square.and.pencil") }
                .help("New request (⌘N)")
            Button { model.clear() } label: { Label("Clear", systemImage: "trash") }
                .disabled(model.flows.isEmpty)
                .help("Remove every request from the list; Undo brings them back (⌘K)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let settings = model.settings.value
            let activeTools = ToolsView.Tool.allCases
                .reduce(0) { $0 + ($1 == .sslProxying ? 0 : $1.activeCount(in: settings)) }
            Button { model.show(.breakpoints) } label: { Label("Breakpoints", systemImage: model.hits.isEmpty ? "pause.circle" : "pause.circle.fill") }
                .badge(model.hits.count)
                .help(model.hits.isEmpty ? "Breakpoints (⌘B)" : "\(model.hits.count) paused at a breakpoint (⌘B)")
            Button { model.show(.tools) } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .badge(activeTools)
                .help(activeTools > 0 ? "\(activeTools) tool rules are changing traffic (⌘T)" : "Map Local, Block List, Scripting and the other tools (⌘T)")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Converter…", systemImage: "arrow.left.arrow.right.square") { model.show(.converter) }
                Button("Set Up a Device…", systemImage: "iphone.gen3") { model.show(.devices) }
                Divider()
                Button("Keyboard Shortcuts", systemImage: "keyboard") { model.show(.help) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Converter (⇧⌘U), device setup (⇧⌘D), shortcuts (⌘/)")
        }
    }
}
