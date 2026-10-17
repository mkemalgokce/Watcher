import ArgumentParser
import Foundation
import WatcherCore

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
