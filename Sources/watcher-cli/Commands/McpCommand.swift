import ArgumentParser
import Foundation
import WatcherCore

struct Mcp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Watcher as an MCP server on stdin/stdout so an AI agent can inspect traffic and manage rules."
    )

    @Option(help: "Port to listen on (default: from settings).") var port: Int?

    func run() async throws {
        try await run(in: .live)
    }

    func run(in environment: CLIEnvironment) async throws {
        // stdout carries the protocol, so diagnostics go to stderr.
        let log = environment.errorOutput
        let (engine, bound) = try await environment.startEngine(port: port) { log("[watcher] \($0)") }
        log("[watcher] MCP server ready; proxy on 127.0.0.1:\(bound)")
        environment.restoreLeftoverSystemProxy { log("[watcher] \($0)") }

        let answer = engine.mcpHandler()
        while let line = environment.readLine() {
            guard !line.isEmpty, let reply = await answer(line) else { continue }
            environment.output(reply)
        }
        try? await engine.stop()
    }
}
