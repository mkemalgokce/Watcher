import SwiftUI
import WatcherCore

/// The menu bar. Every command also exists as a toolbar button or context-menu item; the shortcuts live here.
public struct WatcherCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow
    public init(model: AppModel) {
        self.model = model
    }

    public var body: some Commands {
        // Two groups: older SDKs build at most ten commands per block.
        Group {
            SidebarCommands()
            ToolbarCommands()

            CommandGroup(replacing: .appInfo) {
                Button("About Watcher") { openWindow(id: "about") }
            }

            CommandGroup(replacing: .newItem) {
                Button("New Request…") { model.router.show(.compose) }.keyboardShortcut("n")
                Button("New Request from cURL in Clipboard") { model.actions.composeFromClipboardCurl() }
                    .keyboardShortcut("n", modifiers: [.command, .option])
                Divider()
                Button("Open…") { model.sessionFiles.importFile() }.keyboardShortcut("o")
                Menu("Workspaces") {
                    ForEach(model.workspaces.names, id: \.self) { name in Button(name) { model.workspaces.open(name) } }
                    if !model.workspaces.names.isEmpty {
                        Divider()
                    }
                    Button("Save Current as…") { model.router.askWorkspaceName = true }
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Session…") { model.sessionFiles.saveSession() }.keyboardShortcut("s")
                Button("Export HAR…") { model.sessionFiles.exportHAR() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export CSV…") { model.sessionFiles.exportCSV() }
            }
            CommandGroup(replacing: .textEditing) {
                Button("Find…") { Find.show { model.router.requestSearchFocus() } }.keyboardShortcut("f")
                Button("Find in Body") { Find.findInBody() }.keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { Find.perform(.nextMatch) }.keyboardShortcut("g")
                Button("Find Previous") { Find.perform(.previousMatch) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                item("Delete Request", .delete, in: model.requestCommands(for: model.list.selectedFlow))
                    .keyboardShortcut(.delete, modifiers: .command)
                Button("Clear Session") { model.actions.clear() }.keyboardShortcut("k")
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("All Requests") { model.list.sidebar = .all }.keyboardShortcut("1")
                Button("Starred") { model.list.sidebar = .starred }.keyboardShortcut("2")
                Button("Errors") { model.list.sidebar = .errors }.keyboardShortcut("3")
                Button("WebSocket") { model.list.sidebar = .webSocket }.keyboardShortcut("4")
                Divider()
                Button("Show Body Preview") { model.viewer.mode = .preview }
                    .keyboardShortcut("1", modifiers: [.command, .control])
                Button("Show Body Pretty") { model.viewer.mode = .pretty }
                    .keyboardShortcut("2", modifiers: [.command, .control])
                Button("Show Body Raw") { model.viewer.mode = .raw }
                    .keyboardShortcut("3", modifiers: [.command, .control])
                Button("Show Body as Hex") { model.viewer.mode = .hex }
                    .keyboardShortcut("4", modifiers: [.command, .control])
                Button("Show Request") { model.router.exchangeSide = .request }
                    .keyboardShortcut("[", modifiers: [.command, .option])
                Button("Show Response") { model.router.exchangeSide = .response }
                    .keyboardShortcut("]", modifiers: [.command, .option])
                Button("Filter JSON Body") { model.viewer.toggleJSONFilter() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Toggle Line Wrapping") { model.viewer.toggleLineWrapping() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Clear Filters") { model.list.clearFilters() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Toggle("Hide Apple Traffic", isOn: Binding(get: { model.settings.hideAppleTraffic }, set: { model.settings.hideAppleTraffic = $0 }))
            }
        }

        Group {
            CommandMenu("Request") {
                let commands = model.requestCommands(for: model.list.selectedFlow)
                item("Repeat", .repeatRequest, in: commands).keyboardShortcut("r")
                item("Edit & Repeat…", .editAndRepeat, in: commands)
                    .keyboardShortcut("r", modifiers: [.command, .option])
                Divider()
                item(commands.starTitle, .toggleStar, in: commands).keyboardShortcut("d")
                item("Copy as cURL", .copyCURL, in: commands).keyboardShortcut("c", modifiers: [.command, .shift])
                item("Copy URL", .copyURL, in: commands).keyboardShortcut("c", modifiers: [.command, .option])
                item("Mock This Response", .mockResponse, in: commands)
                    .keyboardShortcut("m", modifiers: [.command, .option])
                item("Set as Compare Base", .setCompareBase, in: commands)
                    .keyboardShortcut("b", modifiers: [.command, .shift])
            }

            CommandMenu("Proxy") {
                Button(model.proxy.isRunning ? "Pause Recording" : "Record") { model.proxy.toggleRunning() }
                    .keyboardShortcut("e").disabled(model.proxy.isSwitchingProxy)
                Toggle("System Proxy", isOn: Binding(get: { model.proxy.systemProxyOn }, set: model.proxy.setSystemProxy))
                    .keyboardShortcut("y", modifiers: [.command, .shift]).disabled(!model.proxy.isRunning)
                Divider()
                Button("Breakpoints…") { model.router.show(.breakpoints) }.keyboardShortcut("b")
                Button("Tools…") { model.router.show(.tools) }.keyboardShortcut("t")
                Button("Converter…") { model.router.show(.converter) }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model.router.show(.help) }.keyboardShortcut("/")
                Button("Getting Started…") { model.router.show(.welcome) }
                Divider()
                Link("Watcher on GitHub", destination: ProjectLinks.repository)
                Link("Report an Issue…", destination: ProjectLinks.issues)
                Link("Sponsor Watcher…", destination: ProjectLinks.sponsor)
            }

            CommandMenu("Certificate") {
                Button("Set Up a Device…") { model.router.show(.devices) }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(model.devices.macTrusted ? "Trusted on This Mac" : "Install & Trust on This Mac…") { Task { await model.devices.trustOnMac() } }
                    .disabled(model.devices.macTrusted)
                Button("Show Root Certificate in Finder") { model.actions.revealCertificate() }
                Divider()
                Button("Copy Certificate Page URL") {
                    model.actions.copy(model.devices.certificatePageURL)
                }
            }
        }
    }

    private func item(
        _ title: String, _ command: RequestCommands.Command, in commands: RequestCommands
    ) -> some View {
        Button(title) { commands.perform(command) }.disabled(!commands.isEnabled(command))
    }
}
