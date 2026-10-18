import Foundation
import SnapshotTesting
import Testing
import WatcherCore
import WatcherTestSupport

/// What other programs read from Watcher: the MCP tool list agents are prompted with, and the exported files.
@Suite(.tags(.snapshot))
struct InterfaceSnapshotTests {
    private static let started = Date(timeIntervalSince1970: 1_700_000_000)

    private static var flows: [Flow] {
        var answered = Flow.fixture(
            sequence: 1,
            request: .fixture(method: "POST", url: "https://api.example.com/v1/users?page=2", body: Data("{}".utf8)),
            response: .fixture(
                status: 201, headers: [Header("Content-Type", "application/json")], body: Data(#"{"id":7}"#.utf8)
            ),
            duration: 0.25
        )
        let formula = RequestRecord.fixture(url: "http://example.com/=cmd")
        var pending = Flow.fixture(sequence: 2, request: formula, response: nil, state: .pending)
        answered.startedAt = started
        pending.startedAt = started.addingTimeInterval(1)
        return [answered, pending]
    }

    private func reply(to line: String) async throws -> String {
        let server = try MCPServer(engine: WatcherEngine.inMemory(), localAddresses: { ["192.168.1.5"] })
        let handled = await server.handle(line)
        let answer = try #require(handled)
        let object = try JSONSerialization.jsonObject(with: Data(answer.utf8))
        let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return try #require(String(bytes: data, encoding: .utf8))
    }

    @Test
    func theMCPToolListStaysTheSame() async throws {
        let listed = try await reply(to: #"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
        assertSnapshot(of: listed, as: .lines)
    }

    @Test
    func theMCPRuleListStaysTheSame() async throws {
        let call = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"list_rules","arguments":{}}}"#
        let rules = try await reply(to: call)
        assertSnapshot(of: rules, as: .lines)
    }

    @Test
    func theHARExportStaysTheSame() throws {
        let data = try HAR.export(Self.flows)
        try assertSnapshot(of: #require(String(bytes: data, encoding: .utf8)), as: .lines)
    }

    @Test
    func theCSVExportStaysTheSame() throws {
        try assertSnapshot(of: #require(String(bytes: CSVExporter.export(Self.flows), encoding: .utf8)), as: .lines)
    }
}
