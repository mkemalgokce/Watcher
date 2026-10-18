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
                Button("New Request…") { model.show(.compose) }.keyboardShortcut("n")
                Button("New Request from cURL in Clipboard") { model.composeFromClipboardCurl() }.keyboardShortcut("n", modifiers: [.command, .option])
                Divider()
                Button("Open…") { model.sessionFiles.importFile() }.keyboardShortcut("o")
                Menu("Workspaces") {
                    ForEach(model.workspaces.names, id: \.self) { name in Button(name) { model.workspaces.open(name) } }
                    if !model.workspaces.names.isEmpty {
                        Divider()
                    }
                    Button("Save Current as…") { model.askWorkspaceName = true }
                }
            }
            CommandGroup(replacing: .saveItem) {
                Button("Save Session…") { model.sessionFiles.saveSession() }.keyboardShortcut("s")
                Button("Export HAR…") { model.sessionFiles.exportHAR() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button("Export CSV…") { model.sessionFiles.exportCSV() }
            }
            CommandGroup(replacing: .textEditing) {
                Button("Find…") { Find.show { model.requestSearchFocus() } }.keyboardShortcut("f")
                Button("Find in Body") { Find.findInBody() }.keyboardShortcut("f", modifiers: [.command, .option])
                Button("Find Next") { Find.perform(.nextMatch) }.keyboardShortcut("g")
                Button("Find Previous") { Find.perform(.previousMatch) }.keyboardShortcut("g", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Delete Request") { model.delete(model.selection.map { [$0] } ?? []) }
                    .keyboardShortcut(.delete, modifiers: .command).disabled(model.selection == nil)
                Button("Clear Session") { model.clear() }.keyboardShortcut("k")
            }
            CommandGroup(after: .sidebar) {
                Divider()
                Button("All Requests") { model.sidebar = .all }.keyboardShortcut("1")
                Button("Starred") { model.sidebar = .starred }.keyboardShortcut("2")
                Button("Errors") { model.sidebar = .errors }.keyboardShortcut("3")
                Button("WebSocket") { model.sidebar = .webSocket }.keyboardShortcut("4")
                Divider()
                Button("Show Body Preview") { model.preferences.showBody(.preview) }
                    .keyboardShortcut("1", modifiers: [.command, .control])
                Button("Show Body Pretty") { model.preferences.showBody(.pretty) }
                    .keyboardShortcut("2", modifiers: [.command, .control])
                Button("Show Body Raw") { model.preferences.showBody(.raw) }
                    .keyboardShortcut("3", modifiers: [.command, .control])
                Button("Show Body as Hex") { model.preferences.showBody(.hex) }
                    .keyboardShortcut("4", modifiers: [.command, .control])
                Button("Show Request") { model.exchangeSide = .request }.keyboardShortcut("[", modifiers: [.command, .option])
                Button("Show Response") { model.exchangeSide = .response }.keyboardShortcut("]", modifiers: [.command, .option])
                Button("Filter JSON Body") { model.preferences.toggleJSONFilter() }
                    .keyboardShortcut("j", modifiers: [.command, .shift])
                Button("Toggle Line Wrapping") { model.preferences.toggleLineWrapping() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Divider()
                Button("Clear Filters") { model.query.reset(); model.sidebar = .all }.keyboardShortcut("l", modifiers: [.command, .shift])
                Toggle("Hide Apple Traffic", isOn: Binding(get: { model.settings.hideAppleTraffic }, set: { model.settings.hideAppleTraffic = $0 }))
            }
        }

        Group {
            CommandMenu("Request") {
                let selected = model.selectedFlow
                Button("Repeat") {
                    if let selected {
                        model.repeatRequest(selected.request)
                    }
                }
                .keyboardShortcut("r").disabled(selected == nil)
                Button("Edit & Repeat…") {
                    if let selected {
                        model.editAndRepeat(selected)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .option]).disabled(selected == nil)
                Divider()
                Button(selected?.isStarred == true ? "Remove Star" : "Star") {
                    if let selected {
                        model.toggleStar([selected.id])
                    }
                }
                .keyboardShortcut("d").disabled(selected == nil)
                Button("Copy as cURL") {
                    if let selected {
                        model.copy(model.code(for: selected.request, as: .curl))
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .shift]).disabled(selected == nil)
                Button("Copy URL") {
                    if let selected {
                        model.copy(selected.request.url)
                    }
                }
                .keyboardShortcut("c", modifiers: [.command, .option]).disabled(selected == nil)
                Button("Mock This Response") {
                    if let selected {
                        model.mockResponse(selected)
                    }
                }
                .keyboardShortcut("m", modifiers: [.command, .option]).disabled(selected?.response == nil)
                Button("Set as Compare Base") {
                    if let selected {
                        model.compare(withBase: selected)
                    }
                }
                .keyboardShortcut("b", modifiers: [.command, .shift]).disabled(selected == nil)
            }

            CommandMenu("Proxy") {
                Button(model.isRunning ? "Pause Recording" : "Record") { model.toggleRunning() }
                    .keyboardShortcut("e").disabled(model.isSwitchingProxy)
                Toggle("System Proxy", isOn: Binding(get: { model.systemProxyOn }, set: model.setSystemProxy))
                    .keyboardShortcut("y", modifiers: [.command, .shift]).disabled(!model.isRunning)
                Divider()
                Button("Breakpoints…") { model.show(.breakpoints) }.keyboardShortcut("b")
                Button("Tools…") { model.show(.tools) }.keyboardShortcut("t")
                Button("Converter…") { model.show(.converter) }.keyboardShortcut("u", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts") { model.show(.help) }.keyboardShortcut("/")
                Button("Getting Started…") { model.show(.welcome) }
                Divider()
                Link("Watcher on GitHub", destination: ProjectLinks.repository)
                Link("Report an Issue…", destination: ProjectLinks.issues)
                Link("Sponsor Watcher…", destination: ProjectLinks.sponsor)
            }

            CommandMenu("Certificate") {
                Button("Set Up a Device…") { model.show(.devices) }.keyboardShortcut("d", modifiers: [.command, .shift])
                Button(model.devices.macTrusted ? "Trusted on This Mac" : "Install & Trust on This Mac…") { Task { await model.devices.trustOnMac() } }
                    .disabled(model.devices.macTrusted)
                Button("Show Root Certificate in Finder") { model.revealCertificate() }
                Divider()
                Button("Copy Certificate Page URL") {
                    model.copy(model.lanProxyAddress.map { "http://\($0)" } ?? "http://watcher.cert")
                }
            }
        }
    }
}
