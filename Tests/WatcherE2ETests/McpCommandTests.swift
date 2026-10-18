import Foundation
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.e2e, .network))
struct McpCommandTests {
    private static let initialize = #"{"jsonrpc":"2.0","id":1,"method":"initialize"}"# + "\n"

    @Test
    func answersOneLinePerRequestOnStandardOutputAndExitsAtTheEndOfInput() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let input = "\n" + Self.initialize + #"{"jsonrpc":"2.0","method":"notifications/initialized"}"# + "\n"

            let mcp = try WatcherCLIRun.run(["mcp", "--port", "0"], home: home.url, input: input)

            #expect(mcp.status == 0)
            let lines = mcp.text.split(separator: "\n")
            try #require(lines.count == 1, "stdout must carry only the protocol: \(mcp.text)")
            let reply = try JSONSerialization.jsonObject(with: Data(lines[0].utf8)) as? [String: Any]
            #expect(reply?["id"] as? Int == 1)
            let serverInfo = (reply?["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
            #expect(serverInfo?["name"] as? String == "watcher")
        }
    }

    @Test
    func reportsReadinessOnStandardError() throws {
        try withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let mcp = try WatcherCLIRun.run(
                ["mcp", "--port", "0"],
                home: home.url,
                input: "",
                includingErrorOutput: true
            )
            #expect(mcp.status == 0)
            #expect(mcp.text.contains("[watcher] MCP server ready; proxy on 127.0.0.1:"))
        }
    }
}
