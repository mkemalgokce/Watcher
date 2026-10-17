import ArgumentParser
import Foundation
import WatcherCore

struct Mcp: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Run Watcher as an MCP server on stdin/stdout so an AI agent can inspect traffic and manage rules."
    )

    @Option(help: "Port to listen on (default: from settings).") var port: Int?

    func run() async throws {
        let engine = try WatcherEngine()
        // stdout carries the protocol, so diagnostics go to stderr.
        engine.onLog = { FileHandle.standardError.write(Data("[watcher] \($0)\n".utf8)) }
        let bound = try await engine.start(port: port)
        FileHandle.standardError.write(Data("[watcher] MCP server ready; proxy on 127.0.0.1:\(bound)\n".utf8))

        let server = MCPServer(engine: engine)
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty, let reply = await server.handle(line) else { continue }
            print(reply)
            fflush(stdout)
        }
        try? await engine.stop()
    }
}
