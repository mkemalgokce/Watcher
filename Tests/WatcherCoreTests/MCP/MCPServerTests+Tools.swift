import AsyncHTTPClient
import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension MCPServerTests {
    /// What each tool reads and changes, and how it refuses what it cannot do.
    @Suite(.tags(.unit))
    struct Tools {
        private let tests: MCPServerTests

        init() throws {
            tests = try MCPServerTests()
        }

        private func call(
            _ name: String,
            _ arguments: String = "{}",
            on server: MCPServer? = nil
        ) async throws -> (text: String, isError: Bool) {
            let params = #"{"name":"\#(name)","arguments":\#(arguments)}"#
            let line = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":\#(params)}"#
            let reply = try await tests.json((server ?? tests.server).handle(line))
            let result = try #require(reply["result"] as? [String: Any])
            return (tests.text(of: reply), result["isError"] as? Bool ?? false)
        }

        private func engine(upstream: UpstreamStub) throws -> WatcherEngine {
            let directory = URL(fileURLWithPath: "/fake-home/.watcher")
            return try WatcherEngine(directory: directory, files: FileAccessFake().access) {
                ProxyServer(store: $0, authority: $1, upstream: upstream)
            }
        }

        private var settings: WatcherSettings {
            tests.engine.settings.value
        }

        // MARK: Reading

        @Test(arguments: [#"{"sequence":"99"}"#, #"{"sequence":"abc"}"#])
        func aFlowThatDoesNotExistIsAnError(arguments: String) async throws {
            let result = try await call("get_flow_detail", arguments)
            #expect(result.isError)
            #expect(result.text == "No request with that sequence number")
        }

        @Test
        func aFlowWithoutAResponseSaysSo() async throws {
            let request = RequestRecord.fixture(host: "a.test", path: "/x")
            tests.engine.store.load([Flow.fixture(request: request, response: nil, state: .pending)])
            let text = try await call("get_flow_detail", #"{"sequence":"1"}"#).text
            #expect(text.hasPrefix("GET https://a.test/x\n"))
            #expect(text.hasSuffix("--- response ---\n(no response)"))
        }

        @Test
        func aLongBodyIsCutAtTwentyThousandCharacters() async throws {
            let body = Data(String(repeating: "Z", count: 25000).utf8)
            let response = ResponseRecord.fixture(headers: [Header("Content-Type", "text/plain")], body: body)
            tests.engine.store.load([Flow.fixture(response: response)])
            let text = try await call("get_flow_detail", #"{"sequence":"1"}"#).text
            #expect(text.count(where: { $0 == "Z" }) == 20000)
        }

        @Test
        func webSocketMessagesShowTheirDirectionAndTextOrSize() async throws {
            var flow = Flow.fixture()
            flow.webSocketMessages = [
                WebSocketMessage(direction: .clientToServer, kind: .text, payload: Data("hi".utf8)),
                WebSocketMessage(direction: .serverToClient, kind: .binary, payload: Data([0xFF, 0xFE, 0xFD])),
            ]
            tests.engine.store.load([flow])
            let text = try await call("get_websocket_messages", #"{"sequence":"1"}"#).text
            #expect(text == "→ text hi\n← binary <3 bytes>")
        }

        @Test
        func clearingTheSessionRemovesEveryFlow() async throws {
            tests.engine.store.load([Flow.fixture(), .fixture(sequence: 2)])
            #expect(try await call("clear_session").text == "OK")
            #expect(tests.engine.store.all.isEmpty)
        }

        @Test
        func theRuleListShowsEveryToolWithItsState() async throws {
            try tests.engine.settings.update {
                $0.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "*ads*"))])
                $0.mapLocal = RuleSet(isEnabled: false, rules: [])
                $0.noCaching = true
                $0.throttle.isEnabled = true
                $0.throttle.profile = NetworkProfile.presets[0]
            }
            let expected = [
                "block-list: on, 1 rule(s)", "allow-list: off, 0 rule(s)", "map-local: off, 0 rule(s)",
                "map-remote: off, 0 rule(s)", "breakpoint: off, 0 rule(s)", "scripting: off, 0 rule(s)",
                "dns-spoofing: off, 0 rule(s)", "reverse-proxy: off, 0 rule(s)", "network-condition: on (3G)",
                "no-caching: on",
            ].joined(separator: "\n")
            #expect(try await call("list_rules").text == expected)
        }

        @Test
        func theSSLProxyingListShowsIncludedAndExcludedHosts() async throws {
            try tests.engine.settings.update {
                $0.sslProxying.include = ["*"]
                $0.sslProxying.exclude = ["a.test", "b.test"]
            }
            #expect(try await call("get_ssl_proxying_list").text == "include: *\nexclude: a.test, b.test")
        }

        // MARK: Creating rules

        @Test
        func eachRuleToolSwitchesItsToolOnAndAddsOneRule() async throws {
            let calls: [(String, String)] = [
                ("create_allow_list", #"{"pattern":"*ok*"}"#),
                ("create_map_local", #"{"pattern":"*a*","file_path":"/tmp/a.json"}"#),
                ("create_breakpoint", #"{"pattern":"*b*"}"#),
                ("create_dns_spoofing", #"{"host":"a.test","address":"127.0.0.1"}"#),
                ("create_scripting_rule", #"{"pattern":"*s*","source":"function onRequest(r){return r}"}"#),
            ]
            for (name, arguments) in calls {
                let result = try await call(name, arguments)
                #expect(result.text == "OK" && !result.isError, "\(name): \(result.text)")
            }
            #expect(settings.allowList.isEnabled && settings.allowList.rules.map(\.matching.pattern) == ["*ok*"])
            #expect(settings.mapLocal.isEnabled && settings.mapLocal.rules.count == 1)
            #expect(settings.mapLocal.rules.first?.source == .file("/tmp/a.json"))
            #expect(settings.breakpoints.isEnabled && settings.breakpoints.rules.map(\.matching.pattern) == ["*b*"])
            #expect(settings.dnsSpoofing.isEnabled && settings.dnsSpoofing.rules.map(\.host) == ["a.test"])
            #expect(settings.scripting.isEnabled)
            #expect(settings.scripting.rules.map(\.source) == ["function onRequest(r){return r}"])
        }

        @Test(arguments: [
            (#"{"pattern":"*","host":"b.test"}"#, "b.test" as String?, nil as String?),
            (#"{"pattern":"*","path":"/v2"}"#, nil as String?, "/v2" as String?),
            (#"{"pattern":"*","host":"b.test","path":"/v2"}"#, "b.test" as String?, "/v2" as String?),
        ])
        func aMapRemoteRuleNeedsAHostOrAPath(arguments: String, host: String?, path: String?) async throws {
            #expect(try await call("create_map_remote", arguments).text == "OK")
            let destination = try #require(settings.mapRemote.rules.first?.destination)
            #expect(destination.host == host)
            #expect(destination.path == path)
        }

        @Test(arguments: [#"{"pattern":"*"}"#, #"{"pattern":"*","host":""}"#, #"{"pattern":"*","host":" ","path":""}"#])
        func aMapRemoteRuleThatMapsNothingIsRefused(arguments: String) async throws {
            let result = try await call("create_map_remote", arguments)
            #expect(result.isError)
            #expect(settings.mapRemote.rules.isEmpty)
        }

        @Test
        func aNetworkConditionTakesAPresetOrASavedProfile() async throws {
            #expect(try await call("create_network_condition", #"{"preset":"LTE"}"#).text == "OK")
            #expect(settings.throttle.isEnabled && settings.throttle.profile.name == "LTE")
            let mine = NetworkProfile(name: "Mine", downloadKbps: 5)
            try tests.engine.settings.update { $0.throttle.customProfiles = [mine] }
            #expect(try await call("create_network_condition", #"{"preset":"Mine"}"#).text == "OK")
            #expect(settings.throttle.profile.downloadKbps == 5)
        }

        @Test
        func anUnknownNetworkPresetIsAnError() async throws {
            let result = try await call("create_network_condition", #"{"preset":"Dial-up"}"#)
            #expect(result.isError)
            #expect(result.text == "Unknown preset")
            #expect(!settings.throttle.isEnabled)
        }

        @Test
        func aReverseProxyDefaultsToPort443() async throws {
            let result = try await call("create_reverse_proxy", #"{"local_port":"8080","remote_host":"a.test"}"#)
            #expect(result.text == "OK")
            let rule = try #require(settings.reverseProxy.rules.first)
            #expect((rule.localPort, rule.remoteHost, rule.remotePort) == (8080, "a.test", 443))
        }

        @Test(arguments: [
            #"{"local_port":"x","remote_host":"a.test"}"#,
            #"{"local_port":"0","remote_host":"a.test"}"#,
            #"{"local_port":"70000","remote_host":"a.test"}"#,
            #"{"local_port":"8080","remote_host":"a.test","remote_port":"99999"}"#,
        ])
        func aReverseProxyWithAnUnusablePortIsRefused(arguments: String) async throws {
            let result = try await call("create_reverse_proxy", arguments)
            #expect(result.isError, "\(arguments)")
            #expect(settings.reverseProxy.rules.isEmpty)
        }

        @Test
        func aSettingsWriteThatFailsIsAnErrorNotACrash() async throws {
            let files = FileAccessFake()
            let server = try MCPServer(engine: WatcherEngine.inMemory(files: files), localAddresses: { [] })
            files.fail(.writePrivately)
            #expect(try await call("create_blacklist", #"{"pattern":"*"}"#, on: server).isError)
        }

        // MARK: Compose

        @Test(arguments: ["/relative/path", "nothing", ""])
        func composeNeedsAnAbsoluteURL(url: String) async throws {
            let result = try await call("create_compose_http", #"{"url":"\#(url)"}"#)
            #expect(result.isError)
        }

        @Test
        func composeOnAStoppedEngineReports503() async throws {
            let result = try await call("create_compose_http", #"{"url":"https://a.test/x"}"#)
            #expect(result.text.hasPrefix("HTTP 503"))
        }

        @Test
        func composeSendsTheRequestItDescribesAndSkipsMalformedHeaderLines() async throws {
            let created = HTTPClientResponse(status: .created, body: .bytes(ByteBuffer(string: "made")))
            let upstream = UpstreamStub(response: { created })
            let engine = try engine(upstream: upstream)
            _ = try await engine.start(port: 0)
            let headers = #"X-A: 1\nnot a header\nX-B:2"#
            let arguments = #"{"method":"post","url":"http://a.test:8080/p?q=1","headers":"\#(headers)","body":"data"}"#
            let result = try await call("create_compose_http", arguments, on: MCPServer(engine: engine))
            try await engine.stop()
            #expect(result.text == "HTTP 201\nmade")
            let sent = try #require(upstream.sent.first?.record)
            #expect((sent.method, sent.host, sent.port, sent.path) == ("POST", "a.test", 8080, "/p?q=1"))
            #expect(sent.headers.filter { ["X-A", "X-B"].contains($0.name) }.map(\.value) == ["1", "2"])
            #expect(!sent.headers.contains { $0.name.hasPrefix("not") })
            #expect(sent.body == Data("data".utf8))
        }
    }
}
