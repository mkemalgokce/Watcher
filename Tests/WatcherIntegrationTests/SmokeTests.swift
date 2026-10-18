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

    @Test @MainActor
    func appModelOnTheShippedWiringKeepsToItsFolderAndDoesNotListen() throws {
        try withTemporaryDirectory(prefix: "watcher-smoke") { directory in
            let commands = CommandRunnerSpy()
            let model = try AppModel(dependencies: .preview(in: directory.url, commands: commands.runner))

            #expect(!model.proxy.isRunning)
            #expect(model.list.flows.isEmpty)
            #expect(commands.commands.isEmpty, "no networksetup or other program runs: \(commands.calls)")
            #expect(FileManager.default.fileExists(atPath: directory.appending("watcher-ca.pem").path))
        }
    }

    @Test(.tags(.network)) @MainActor
    func appModelOnALiveEngineListsWhatPassesThroughTheProxy() async throws {
        try await withHarness { harness in
            let model = try AppModel(dependencies: .test(
                engine: harness.engine, sleep: liveSleep, runner: AnyPortRunner(harness.engine)
            ))
            model.observeEngine()
            let response = try await harness.get("/from-the-app")
            #expect(response.status == 200)
            let list = model.list
            #expect(await eventually { list.flows.contains { $0.request.path == "/from-the-app" } })
        }
    }

    @Test(
        .tags(.network, .externalTool),
        .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
    )
    func anHTTPSConnectIsDecryptedAndRecordedThroughTheProxy() async throws {
        try await withHarness { harness in
            _ = try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "upstream.test", verify: false) + """

            t.sendall(b"GET /secure HTTP/1.1\\r\\nHost: upstream.test\\r\\nConnection: close\\r\\n\\r\\n")
            t.settimeout(1)
            try: t.recv(4096)
            except Exception: pass
            """)
            let recorded = await eventually(timeout: 5) {
                harness.engine.store.all.contains { $0.request.path == "/secure" }
            }
            let flow = try #require(harness.engine.store.all.first { $0.request.path == "/secure" })
            #expect(recorded)
            #expect(flow.request.scheme == "https")
            #expect(flow.request.host == "upstream.test")
        }
    }
}
