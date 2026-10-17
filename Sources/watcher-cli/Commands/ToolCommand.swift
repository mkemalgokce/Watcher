import ArgumentParser
import Foundation
import WatcherCore

/// Tools a running (or later started) Watcher picks up from the shared settings file.
enum ToolName: String, CaseIterable, ExpressibleByArgument {
    case breakpoint, mapLocal = "map-local", mapRemote = "map-remote", scripting
    case blockList = "block-list", allowList = "allow-list", reverseProxy = "reverse-proxy"
    case networkCondition = "network-condition", noCaching = "no-caching"
    case dnsSpoofing = "dns-spoofing", externalProxy = "external-proxy"

    func set(_ enabled: Bool, in settings: inout WatcherSettings) {
        switch self {
        case .breakpoint: settings.breakpoints.isEnabled = enabled
        case .mapLocal: settings.mapLocal.isEnabled = enabled
        case .mapRemote: settings.mapRemote.isEnabled = enabled
        case .scripting: settings.scripting.isEnabled = enabled
        case .blockList: settings.blockList.isEnabled = enabled
        case .allowList: settings.allowList.isEnabled = enabled
        case .reverseProxy: settings.reverseProxy.isEnabled = enabled
        case .networkCondition: settings.throttle.isEnabled = enabled
        case .noCaching: settings.noCaching = enabled
        case .dnsSpoofing: settings.dnsSpoofing.isEnabled = enabled
        case .externalProxy: settings.externalProxy.isEnabled = enabled
        }
    }
}

struct Tool: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Switch a debugging tool on or off.")

    enum State: String, ExpressibleByArgument { case on, off }

    @Argument(help: "One of: \(ToolName.allCases.map(\.rawValue).joined(separator: ", ")).") var tool: ToolName
    @Argument var state: State

    func run() throws {
        let store = SettingsStore(url: WatcherPaths.supportDirectory.appendingPathComponent("settings.json"))
        try store.update { tool.set(state == .on, in: &$0) }
        print("\(tool.rawValue): \(state.rawValue)")
    }
}

struct ImportCharles: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-charles",
        abstract: "Import tool settings (Block/Allow List, Map Local/Remote, Breakpoints, DNS Spoofing) from a Charles Proxy XML export."
    )

    @Argument(help: "Charles settings XML.") var path: String
    @Option(help: "append (add to existing rules) or override (replace the tool rules; port, SSL and other settings are kept).") var mode = "append"

    func run() throws {
        guard let importMode = WatcherSettings.ImportMode(rawValue: mode) else { throw ValidationError("mode must be append or override") }
        let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let incoming = try CharlesSettings.importSettings(from: Data(contentsOf: source))
        let store = SettingsStore(url: WatcherPaths.supportDirectory.appendingPathComponent("settings.json"))
        try store.replace(with: importMode == .override ? store.value.replacingToolRules(with: incoming) : store.value.importing(incoming, mode: .append))
        print("[Import] Charles settings from \(source.path): block \(incoming.blockList.rules.count), allow \(incoming.allowList.rules.count), map local \(incoming.mapLocal.rules.count), map remote \(incoming.mapRemote.rules.count), breakpoints \(incoming.breakpoints.rules.count), DNS \(incoming.dnsSpoofing.rules.count), reverse proxies \(incoming.reverseProxy.rules.count)")
    }
}

struct Rules: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Export or import every tool's rules as one JSON file.",
        subcommands: [Export.self, Import.self, ImportCharles.self]
    )

    private static var store: SettingsStore {
        SettingsStore(url: WatcherPaths.supportDirectory.appendingPathComponent("settings.json"))
    }

    struct Export: ParsableCommand {
        @Argument(help: "Destination file.") var path: String
        @Option(help: "all (every rule) or enabledRules (only enabled ones).") var mode = "all"

        func run() throws {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let exportMode = WatcherSettings.ExportMode(rawValue: mode) else { throw ValidationError("mode must be all or enabledRules") }
            let destination = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            print("[Export] Prepare for exporting Watcher Rules. Mode = \(mode), output = \(destination.path)")
            try encoder.encode(Rules.store.value.exported(exportMode)).write(to: destination, options: .atomic)
        }
    }

    struct Import: ParsableCommand {
        @Argument(help: "JSON file produced by `rules export`.") var path: String
        @Option(help: "append (add to existing rules) or override (replace everything).") var mode = "override"

        func run() throws {
            let source = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            print("[Import] Prepare for importing Watcher Rules. Mode = \(mode), input = \(source.path)")
            let data = try Data(contentsOf: source)
            guard let importMode = WatcherSettings.ImportMode(rawValue: mode) else { throw ValidationError("mode must be append or override") }
            let incoming = try JSONDecoder().decode(WatcherSettings.self, from: data)
            try Rules.store.replace(with: Rules.store.value.importing(incoming, mode: importMode))
            print("Imported")
        }
    }
}
