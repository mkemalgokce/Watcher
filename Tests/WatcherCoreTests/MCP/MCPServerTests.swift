import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct MCPServerTests {
    let engine: WatcherEngine
    let server: MCPServer

    init() throws {
        engine = try WatcherEngine.inMemory()
        server = MCPServer(engine: engine, localAddresses: { ["192.168.1.5", "10.0.0.2"] })
    }

    @Test
    func answersTheProtocolBasics() async throws {
        let initialized = try await json(server.handle(
            #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26"}}"#
        ))
        #expect((initialized["result"] as? [String: Any])?["protocolVersion"] as? String == "2025-03-26")
        let notification = await server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
        #expect(notification == nil)
        let listed = try await json(server.handle(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#))
        let tools = (listed["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        let names = tools?.compactMap { $0["name"] as? String } ?? []
        #expect(
            ["get_flows", "get_flow_detail", "get_websocket_messages", "create_blacklist", "clear_session"]
                .allSatisfy(names.contains)
        )
        let unknown = try await json(server.handle(#"{"jsonrpc":"2.0","id":3,"method":"nope"}"#))
        #expect((unknown["error"] as? [String: Any])?["code"] as? Int == -32601)
        let garbage = try await json(server.handle("{not json"))
        #expect((garbage["error"] as? [String: Any])?["code"] as? Int == -32700)
    }

    @Test
    func toolsChangeSettingsAndValidateArguments() async throws {
        let created = try await callTool("create_blacklist", arguments: #"{"pattern":"*ads*"}"#)
        #expect((created["result"] as? [String: Any])?["isError"] as? Bool == false)
        #expect(engine.settings.value.blockList.rules.map(\.matching.pattern) == ["*ads*"])
        #expect(engine.settings.value.blockList.isEnabled)

        let missing = try await callTool("create_blacklist", arguments: "{}")
        #expect((missing["result"] as? [String: Any])?["isError"] as? Bool == true)

        let request = RequestRecord.fixture(host: "a.com", path: "/x", headers: [Header("Accept", "*/*")])
        engine.store.load([Flow.fixture(request: request, response: nil, state: .pending)])
        let curl = try await callTool("export_flow_curl", arguments: #"{"sequence":"1"}"#)
        #expect(text(of: curl) == "curl 'https://a.com/x' -H 'Accept: */*'")
    }

    @Test(arguments: ["get_flow_detail", "export_flow_curl"])
    func outputRedactsSecrets(tool: String) async throws {
        loadAFlowWithSecrets()
        let shown = try await text(of: callTool(tool, arguments: #"{"sequence":"1"}"#))
        #expect(!shown.contains("SECRET"), "\(shown)")
        #expect(shown.contains("[redacted]"))
    }

    @Test
    func secretsAreShownWhenRedactionIsSwitchedOff() async throws {
        loadAFlowWithSecrets()
        try engine.settings.update { $0.mcpRedaction = false }
        let plain = try await text(of: callTool("get_flow_detail", arguments: #"{"sequence":"1"}"#))
        #expect(plain.contains("SECRET-TOKEN"))
    }

    private func loadAFlowWithSecrets() {
        engine.store.load([Flow.fixture(
            request: .fixture(host: "a.com", headers: [Header("Authorization", "Bearer SECRET-TOKEN")]),
            response: .fixture(headers: [Header("Set-Cookie", "sid=SECRET-COOKIE")]),
            state: .pending
        )])
    }

    @Test
    func anUnknownToolIsAnInvalidParameterError() async throws {
        let reply = try await callTool("make_coffee", arguments: "{}")
        #expect((reply["error"] as? [String: Any])?["code"] as? Int == -32602)
    }

    @Test
    func theStatusNamesThePortStateAndTheMacsLANAddresses() async throws {
        let status = try await text(of: callTool("get_proxy_status", arguments: "{}"))
        #expect(status == "running: false, port: -, requests captured: 0, lan: 192.168.1.5, 10.0.0.2")
    }

    func callTool(_ name: String, arguments: String) async throws -> [String: Any] {
        try await json(server.handle(
            #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(name)","arguments":\#(arguments)}}"#
        ))
    }

    func json(_ line: String?) throws -> [String: Any] {
        let reply = try #require(line)
        return try #require(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
    }

    func text(of reply: [String: Any]) -> String {
        let content = (reply["result"] as? [String: Any])?["content"] as? [[String: Any]]
        return (content?.first?["text"] as? String) ?? ""
    }
}

extension MCPServerTests {
    @Test
    func theCertificateStatusReportsTheEnginesOwnCertificate() async throws {
        let status = try await text(of: callTool("get_certificate_status", arguments: "{}"))
        #expect(status == engine.authority.certificateURL.path)
        #expect(status.hasPrefix("/fake-home/"))
    }
}
