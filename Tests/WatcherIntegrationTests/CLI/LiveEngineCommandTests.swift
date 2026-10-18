import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

/// `start` and `mcp` on the real engine and live wiring, with only the terminal, the home folder and the programs faked.
@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct LiveEngineCommandTests {
    @Test
    func startProxiesARequestAndPrintsItsLineUntilStopped() async throws {
        let origin = TestUpstream()
        try await origin.start()
        do {
            try await startProxyingOnce(from: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    @Test
    func mcpAnswersInitializeOnTheRealEngineAndStopsAtTheEndOfInput() async throws {
        try await withTemporaryDirectory(prefix: "watcher-live-cli") { home in
            let terminal = Terminal(input: [#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#])
            let environment = terminal.environment(home: home.url)

            try await Mcp.parse(["--port", "0"]).run(in: environment)

            let reply = try #require(terminal.printed.first)
            let object = try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any]
            let serverInfo = (object?["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
            #expect(serverInfo?["name"] as? String == "watcher")
            #expect(terminal.printedToErrorOutput.contains { $0.hasPrefix("[watcher] MCP server ready") })
            #expect(terminal.commands.commands.isEmpty)
        }
    }

    private func startProxyingOnce(from origin: TestUpstream) async throws {
        try await withTemporaryDirectory(prefix: "watcher-live-cli") { home in
            let terminal = Terminal()
            let environment = terminal.environment(home: home.url)
            let spoof = DNSSpoofRule(host: "upstream.test", address: "127.0.0.1")
            try environment.settings.update { $0.dnsSpoofing = RuleSet(isEnabled: true, rules: [spoof]) }
            let running = Task { try await Start.parse(["--port", "0"]).run(in: environment) }
            let listening = await eventually(timeout: 30) { terminal.port != nil }
            guard let port = terminal.port, listening else {
                running.cancel()
                throw TestSupportError("start never listened: \(terminal.printed)")
            }

            let url = "http://upstream.test:\(origin.port)/live"
            let body = try await Self.get(url, throughProxyPort: port)
            let printedTheFlow = await eventually(timeout: 10) {
                terminal.printed.contains { $0.contains("200  GET  \(url)") }
            }
            terminal.pressCtrlC()
            try await running.value

            #expect(body.hasPrefix("GET /live "))
            #expect(printedTheFlow, "start prints each finished request: \(terminal.printed)")
            #expect(terminal.commands.commands.isEmpty)
            #expect(FileManager.default.fileExists(atPath: home.appending("settings.json").path))
        }
    }

    private static func get(_ url: String, throughProxyPort port: Int) async throws -> String {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port]
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, _) = try await session.data(from: #require(URL(string: url)))
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }
}

/// The live environment with the terminal and the programs replaced: what the command prints is read back, Ctrl-C is
/// pressed by the test, and `networksetup` and friends are recorded instead of run.
private final class Terminal: @unchecked Sendable {
    let commands = CommandRunnerSpy()
    private let lines = LockedBox<[String]>([])
    private let errorLines = LockedBox<[String]>([])
    private let input: LockedBox<[String]>
    private let stop = LockedBox<AsyncStream<Void>.Continuation?>(nil)
    private let pressed = LockedBox(false)

    init(input: [String] = []) {
        self.input = LockedBox(input)
    }

    var printed: [String] {
        lines.value
    }

    var printedToErrorOutput: [String] {
        errorLines.value
    }

    var port: Int? {
        printed.first { $0.hasPrefix("Watcher listening on 127.0.0.1:") }
            .flatMap { Int($0.split(separator: ":").last ?? "") }
    }

    func pressCtrlC() {
        pressed.mutate { $0 = true }
        stop.value?.yield()
    }

    func environment(home: URL) -> CLIEnvironment {
        var environment = CLIEnvironment.live
        environment.output = { [lines] line in lines.mutate { $0.append(line) } }
        environment.errorOutput = { [errorLines] line in errorLines.mutate { $0.append(line) } }
        environment.readLine = { [input] in
            var line: String?
            input.mutate { line = $0.isEmpty ? nil : $0.removeFirst() }
            return line
        }
        environment.variables = ["WATCHER_HOME": home.path]
        environment.home = home
        environment.currentDirectory = home
        environment.commands = commands.runner
        environment.shutdownSignal = { [stop, pressed] in
            AsyncStream { new in
                stop.mutate { $0 = new }
                if pressed.value {
                    new.yield()
                }
            }
        }
        return environment
    }
}
