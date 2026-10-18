import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@Suite(.timeLimit(.minutes(1)), .tags(.smoke, .integration))
struct SmokeTests {
    @Test(.tags(.network))
    func engineStartsOnAFreePortAndForwardsAGetToTheOrigin() async throws {
        let (port, response) = try await withHarness { harness in
            try await (harness.proxyPort, harness.get("/hello"))
        }
        #expect(port > 0)
        #expect(response.status == 200)
        #expect(response.body.hasPrefix("GET /hello host=upstream.test"))
    }

    @Test
    func sessionSavedToDiskLoadsBackTheSameFlows() throws {
        let directory = try TemporaryDirectory()
        let file = directory.appending("session.watcher")
        let flows = [
            Flow.fixture(sequence: 1),
            .fixture(sequence: 2, request: .fixture(method: "POST", path: "/v1/users"), response: nil),
        ]
        try SessionFile.encode(flows).write(to: file)
        let loaded = try SessionFile.decode(Data(contentsOf: file))
        #expect(loaded.map(\.id) == flows.map(\.id))
        #expect(loaded.map(\.request) == flows.map(\.request))
        #expect(loaded.map(\.response) == flows.map(\.response))
        #expect(loaded.map(\.state) == [.completed, .failed])
    }

    @Test
    func mcpAnswersInitializeAndListsItsToolsOnAStartedEngine() async throws {
        try await withHarness { harness in
            let server = MCPServer(engine: harness.engine, localAddresses: { [] })
            let initialized = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"initialize"}"#)
            let listed = await server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#)
            let info = try JSONSerialization.jsonObject(with: Data(#require(initialized).utf8)) as? [String: Any]
            let serverInfo = (info?["result"] as? [String: Any])?["serverInfo"] as? [String: Any]
            #expect(serverInfo?["name"] as? String == "watcher")
            let result = try JSONSerialization.jsonObject(with: Data(#require(listed).utf8)) as? [String: Any]
            let tools = (result?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
            #expect(tools?.contains { $0["name"] as? String == "get_proxy_status" } == true)
            let status = await server.handle(
                #"{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"get_proxy_status"}}"#
            )
            #expect(try #require(status).contains("running: true"))
        }
    }

    @Test @MainActor
    func appModelBuildsWithoutListening() throws {
        let model = try AppModel.test()
        #expect(model.list.flows.isEmpty)
        #expect(!model.proxy.isRunning)
    }
}
