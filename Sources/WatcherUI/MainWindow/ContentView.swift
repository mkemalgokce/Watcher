import SwiftUI
import WatcherCore

public struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(FlowListViewModel.self) private var list
    @Environment(WorkspacesViewModel.self) private var workspaces
    @Environment(\.openWindow) private var openWindow
    @State private var workspaceName = ""

    public init() {}

    private var filterTokens: Binding<[FilterToken]> {
        Binding(get: { FilterToken.tokens(in: list.query) }, set: { FilterToken.apply($0, to: &list.query) })
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
        .searchable(text: Bindable(list).query.text, tokens: filterTokens, placement: .toolbar, prompt: "Filter requests") {
            Label($0.title, systemImage: $0.symbol)
        }
        .searchSuggestions {
            let present = FilterToken.tokens(in: list.query)
            let hosts = list.counts.domains.map(\.name)
            ForEach(FilterToken.suggestions(for: list.query.text, hosts: hosts, excluding: present)) {
                Label($0.title, systemImage: $0.symbol).searchCompletion($0)
            }
        }
        .modifier(SearchFocus(request: router.searchFocusRequest))
        .toolbar { WatcherToolbar() }
        .safeAreaInset(edge: .top, spacing: 0) { StartupProblemBanner() }
        .safeAreaInset(edge: .bottom, spacing: 0) { StatusBar(viewModel: model.statusBar) }
        .sheet(item: Bindable(router).sheet) { sheet in
            switch sheet {
            case .tools: ToolsView()
            case .breakpoints: BreakpointsView()
            case .compose: ComposeView(now: model.now)
            case .devices: DeviceSetupView()
            case .welcome: WelcomeView()
            case .converter: ConverterView()
            case .help: HelpView()
            }
        }
        .alert("Save Workspace", isPresented: Bindable(router).askWorkspaceName) {
            TextField("Name", text: $workspaceName)
            Button("Save") { workspaces.save(named: workspaceName); workspaceName = "" }
            Button("Cancel", role: .cancel) { workspaceName = "" }
        } message: { Text("Saves the current requests and all tool settings.") }
        .overlay(alignment: .bottom) { NoticeBanner().padding(.bottom, 34) } // above the status bar, clear of the filter bar
        .onChange(of: router.compareWindowRequest) { _, _ in openWindow(id: "compare") }
        .task {
            // Nothing is captured until Record is pressed.
            if !model.onboardingDone {
                router.sheet = .welcome
            }
        }
    }
}

/// Record, Compose and Clear on the left, screens on the right; what the proxy is doing is in the status bar.
/// Record starts the proxy and Pause stops it, so capturing has one switch.
private struct WatcherToolbar: ToolbarContent {
    @Environment(AppModel.self) private var model
    @Environment(WindowRouter.self) private var router
    @Environment(FlowListViewModel.self) private var list
    @Environment(ProxyController.self) private var proxy
    @Environment(BreakpointsViewModel.self) private var breakpoints
    @Environment(RequestActions.self) private var actions

    /// Native toolbar buttons: macOS draws them as Liquid Glass and groups each ToolbarItemGroup into one capsule, as in Xcode.
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { proxy.toggleRunning() } label: {
                Label(
                    proxy.isRunning ? "Pause" : "Record",
                    systemImage: proxy.isRunning ? "pause.fill" : "record.circle"
                )
            }
            .disabled(proxy.isSwitchingProxy)
            .help(proxy.isRunning ? "Recording. Click to stop the proxy (⌘E)" : "Start the proxy and record (⌘E)")
            Button { router.show(.compose) } label: { Label("Compose", systemImage: "square.and.pencil") }
                .help("New request (⌘N)")
            Button { actions.clear() } label: { Label("Clear", systemImage: "trash") }
                .disabled(list.flows.isEmpty)
                .help("Remove every request from the list; Undo brings them back (⌘K)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            let activeTools = ToolsView.Tool.activeRuleCount(in: model.settings.value)
            Button { router.show(.breakpoints) } label: {
                Label("Breakpoints", systemImage: breakpoints.hits.isEmpty ? "pause.circle" : "pause.circle.fill")
            }
            .badge(breakpoints.hits.count)
            .help(
                breakpoints.hits.isEmpty ? "Breakpoints (⌘B)" : "\(breakpoints.hits.count) paused at a breakpoint (⌘B)"
            )
            Button { router.show(.tools) } label: { Label("Tools", systemImage: "wrench.and.screwdriver") }
                .badge(activeTools)
                .help(StatusBarText.toolRulesHelp(activeTools))
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Converter…", systemImage: "arrow.left.arrow.right.square") { router.show(.converter) }
                Button("Set Up a Device…", systemImage: "iphone.gen3") { router.show(.devices) }
                Divider()
                Button("Keyboard Shortcuts", systemImage: "keyboard") { router.show(.help) }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Converter (⇧⌘U), device setup (⇧⌘D), shortcuts (⌘/)")
        }
    }
}
