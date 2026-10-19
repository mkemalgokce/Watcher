import ArgumentParser
import Foundation
import WatcherCore

extension WatcherSettings.ImportMode: ExpressibleByArgument {}

struct ImportCharles: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-charles",
        abstract: "Import tool settings (Block/Allow List, Map Local/Remote, Breakpoints, DNS Spoofing) from a Charles Proxy XML export."
    )

    @Argument(help: "Charles settings XML.") var path: String
    @Option(
        help: """
        append (add to existing rules) or override \
        (replace the tool rules; port, SSL and other settings are kept).
        """
    ) var mode: WatcherSettings.ImportMode = .append

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        let source = environment.url(forPath: path)
        let incoming = try CharlesSettings.importSettings(from: environment.files.read(source))
        let store = environment.settings
        let merged = mode == .override
            ? store.value.replacingToolRules(with: incoming)
            : store.value.importing(incoming, mode: .append)
        try store.replace(with: merged)
        environment.output("[Import] Charles settings from \(source.path): \(Self.counts(of: incoming))")
    }

    private static func counts(of settings: WatcherSettings) -> String {
        let counts: [(String, Int)] = [
            ("block", settings.blockList.rules.count), ("allow", settings.allowList.rules.count),
            ("map local", settings.mapLocal.rules.count), ("map remote", settings.mapRemote.rules.count),
            ("breakpoints", settings.breakpoints.rules.count), ("DNS", settings.dnsSpoofing.rules.count),
            ("reverse proxies", settings.reverseProxy.rules.count),
        ]
        return counts.map { "\($0) \($1)" }.joined(separator: ", ")
    }
}
