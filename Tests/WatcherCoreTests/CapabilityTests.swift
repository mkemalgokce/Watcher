@testable import WatcherCore
import WatcherTestSupport
import XCTest

/// Session, export and inspector capabilities.
final class CapabilityTests: XCTestCase {
    private func sampleFlow() -> Flow {
        let json = [Header("Content-Type", "application/json")]
        var request = RequestRecord.fixture(method: "POST", path: "/v1/x?a=1,2", headers: json)
        request.body = Data(#"{"k":"it's #1"}"#.utf8); request.clientApp = "Google Chrome"
        let response = ResponseRecord.fixture(headers: json, body: Data("ok".utf8))
        var flow = Flow.fixture(sequence: 3, request: request, response: response, state: .pending)
        flow.duration = 0.25
        flow.appliedTools = ["Map Local", "Scripting"]
        return flow
    }

    func testCSVQuotesCommasAndNeutralisesSpreadsheetFormulas() {
        var evil = sampleFlow()
        evil.request.clientApp = "=HYPERLINK(\"http://x\")"
        let csv = String(decoding: CSVExporter.export([sampleFlow(), evil]), as: UTF8.self)
        let lines = csv.components(separatedBy: "\r\n")
        XCTAssertEqual(lines[0], "#,Method,URL,Status,Duration (ms),Request bytes,Response bytes,Content-Type,Tools,Client app")
        XCTAssertEqual(lines[1], "3,POST,\"https://api.example.com/v1/x?a=1,2\",200,250,15,2,application/json,Map Local; Scripting,Google Chrome")
        XCTAssertTrue(lines[2].hasSuffix("\"'=HYPERLINK(\"\"http://x\"\")\""), lines[2])
    }

    func testNewCodeGeneratorsEscapeInterpolationSyntax() {
        let request = sampleFlow().request
        let go = CodeGenerator.generate(request, as: .go)
        XCTAssertTrue(go.contains("http.NewRequest(\"POST\", \"https://api.example.com/v1/x?a=1,2\"") && go.contains("req.Header.Set(\"Content-Type\""))
        let ruby = CodeGenerator.generate(request, as: .ruby)
        XCTAssertTrue(ruby.contains("Net::HTTP::Post.new(uri)") && ruby.contains("it's \\#1"), ruby)
        XCTAssertTrue(CodeGenerator.generate(RequestRecord(method: "GET", scheme: "https", host: "a", port: 443, path: "/", body: Data("#{system('x')}".utf8)), as: .ruby).contains("\\#{system"))
        let php = CodeGenerator.generate(RequestRecord(method: "POST", scheme: "https", host: "a", port: 443, path: "/", body: Data("$x 'q'".utf8)), as: .php)
        XCTAssertTrue(php.contains(#"CURLOPT_POSTFIELDS, '$x \'q\''"#), php)
        XCTAssertEqual(CodeGenerator.Language.allCases.count, 7)
    }

    func testJSONQuery() throws {
        let json = Data(#"{"users":[{"id":1,"email":"a@x"},{"id":2,"email":"b@x","tags":["t"]}],"meta":{"email":"m@x"}}"#.utf8)
        XCTAssertEqual(JSONQuery.run("users[1].id", on: json), "2")
        XCTAssertEqual(JSONQuery.run("$.users[0].email", on: json), "\"a@x\"")
        XCTAssertEqual(try XCTUnwrap(JSONQuery.run("users[*].id", on: json)).filter { !$0.isWhitespace }, "[1,2]")
        XCTAssertEqual(try XCTUnwrap(JSONQuery.run("..email", on: json)).filter { !$0.isWhitespace }, #"["m@x","a@x","b@x"]"#)
        XCTAssertEqual(try XCTUnwrap(JSONQuery.run("email", on: json)).filter { !$0.isWhitespace }, #"["m@x","a@x","b@x"]"#)
        XCTAssertEqual(JSONQuery.run("users[9]", on: json), "")
        XCTAssertNil(JSONQuery.run("a", on: Data("not json".utf8)))
    }

    func testSimulatorInstallRunsSimctlAndRejectsOddDeviceNames() throws {
        final class Calls: @unchecked Sendable { var list: [[String]] = [] }
        let calls = Calls()
        let cert = URL(fileURLWithPath: "/tmp/watcher-ca.pem")
        try SimulatorCertificate.install(certificate: cert, device: "booted") { calls.list.append($0); return "" }
        try SimulatorCertificate.install(certificate: cert, device: "6F2E-AB12") { calls.list.append($0); return "" }
        XCTAssertEqual(calls.list, [["simctl", "keychain", "booted", "add-root-cert", "/tmp/watcher-ca.pem"], ["simctl", "keychain", "6F2E-AB12", "add-root-cert", "/tmp/watcher-ca.pem"]])
        for bad in ["", "booted; rm -rf /", "../x", "a b"] {
            XCTAssertThrowsError(try SimulatorCertificate.install(certificate: cert, device: bad) { _ in "" }, bad)
        }
    }

    func testClientProcessParsesLsofFieldOutput() {
        let output = "p501\ncCurl Tool\nn127.0.0.1:54321->127.0.0.1:9090\np777\ncwatcher-cli\nn127.0.0.1:9090->127.0.0.1:54321\n"
        XCTAssertEqual(ClientProcess.name(forLocalPort: 54321) { _ in output }, "Curl Tool")
        XCTAssertNil(ClientProcess.name(forLocalPort: 1111) { _ in output })
        XCTAssertNil(ClientProcess.name(forLocalPort: 54321) { _ in nil })
    }

    func testRequestsAreAttributedToTheProgramThatSentThemAndCanBeBlockedByIt() async throws {
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }

        func curl() throws -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            process.arguments = ["-s", "-m", "10", "-x", "http://127.0.0.1:\(harness.proxyPort)", "\(harness.originURL)/by-app"]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run(); process.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        XCTAssertTrue(try curl().hasPrefix("GET /by-app"))
        XCTAssertEqual(harness.engine.store.all.first?.request.clientApp, "curl")

        try await harness.reconfigure { $0.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "*", app: "curl"))]) }
        XCTAssertEqual(try curl(), "Blocked by Watcher")
        let other = try await harness.get("/not-curl")
        XCTAssertEqual(other.status, 200, "only curl is blocked, not this test process")
    }

    func testCustomServerCertificateIsPresentedInsteadOfAGeneratedOne() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-p12-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        func openssl(_ arguments: [String]) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl"); process.arguments = arguments
            process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw XCTSkip("openssl \(arguments.first ?? "") failed") }
        }
        let key = directory.appendingPathComponent("k.pem").path, cert = directory.appendingPathComponent("c.pem").path, p12 = directory.appendingPathComponent("id.p12").path
        try openssl(["req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert, "-subj", "/CN=pinned.test", "-days", "2"])
        try openssl(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "pass:secret"])

        let rule = CustomCertificateRule(host: "pinned.test", role: .server, p12Path: p12, passphrase: "secret")
        XCTAssertNoThrow(try CustomCertificates.serverContext(rule))
        var wrong = rule; wrong.passphrase = "nope"
        XCTAssertThrowsError(try CustomCertificates.serverContext(wrong))

        let harness = try Harness()
        try await harness.start { $0.customCertificates = RuleSet(isEnabled: true, rules: [rule]) }
        defer { Task { await harness.stop() } }

        // Handshake through the proxy and read the certificate that comes back.
        let script = """
        import socket, ssl, sys
        for host in ("pinned.test", "other.test"):
            s = socket.create_connection(("127.0.0.1", \(harness.proxyPort)), timeout=10)
            s.sendall(f"CONNECT {host}:443 HTTP/1.1\\r\\nHost: {host}:443\\r\\n\\r\\n".encode()); s.recv(4096)
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
            der = ctx.wrap_socket(s, server_hostname=host).getpeercert(binary_form=True)
            print(host, ssl.DER_cert_to_PEM_cert(der).replace("\\n", "|"))
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-c", script]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw XCTSkip("python3 unavailable") }
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).components(separatedBy: "\n")
        func subjectAndIssuer(_ line: String) throws -> String {
            let pem = line.split(separator: " ", maxSplits: 1)[1].replacingOccurrences(of: "|", with: "\n")
            let tool = Process(); tool.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            tool.arguments = ["x509", "-noout", "-subject", "-issuer"]
            let input = Pipe(), out = Pipe(); tool.standardInput = input; tool.standardOutput = out
            try tool.run(); input.fileHandleForWriting.write(Data(pem.utf8)); input.fileHandleForWriting.closeFile(); tool.waitUntilExit()
            return String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        }
        let pinned = try subjectAndIssuer(XCTUnwrap(output.first { $0.hasPrefix("pinned.test") }))
        let other = try subjectAndIssuer(XCTUnwrap(output.first { $0.hasPrefix("other.test") }))
        XCTAssertTrue(pinned.contains("CN=pinned.test") && !pinned.contains("Watcher Root CA"), pinned)
        XCTAssertTrue(other.contains("Watcher Root CA"), other)
    }

    func testBreakpointTemplatesAndSettingsCompatibility() throws {
        let templates = WatcherSettings().allBreakpointTemplates
        XCTAssertEqual(templates.map(\.status), [401, 404, 429, 500, 503])
        let tooMany = try XCTUnwrap(templates.first { $0.status == 429 })
        XCTAssertEqual(tooMany.headers.value(for: "retry-after"), "60")
        XCTAssertEqual(tooMany.body, #"{"error":"too_many_requests"}"#)
        var settings = WatcherSettings(); settings.breakpointTemplates = [BreakpointTemplate(name: "Teapot", status: 418)]
        XCTAssertEqual(settings.allBreakpointTemplates.last?.name, "Teapot")
        // Settings written before these fields existed still load.
        let old = try JSONDecoder().decode(WatcherSettings.self, from: Data(#"{"port": 1}"#.utf8))
        XCTAssertTrue(old.customCertificates.rules.isEmpty && old.breakpointTemplates.isEmpty)
        // Requests saved before clientApp existed still decode.
        let request = try JSONDecoder().decode(RequestRecord.self, from: Data(#"{"method":"GET","scheme":"http","host":"a","port":80,"path":"/","headers":[],"body":""}"#.utf8))
        XCTAssertNil(request.clientApp)
    }
}

final class MoreCapabilityTests: XCTestCase {
    private func engine() throws -> WatcherEngine {
        try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
    }

    func testComposeWebSocketRecordsHandshakeAndBothDirections() async throws {
        let origin = WebSocketEchoOrigin()
        try await origin.start()
        defer { Task { await origin.stop() } }
        let engine = try engine()

        try await engine.composeWebSocket(url: XCTUnwrap(URL(string: "ws://127.0.0.1:\(origin.port)/chat?room=1")), messages: ["ping1", "ping2"], listenFor: 1)
        let flow = try XCTUnwrap(engine.store.all.first)
        XCTAssertEqual(flow.request.path, "/chat?room=1")
        XCTAssertEqual(flow.response?.status, 101)
        XCTAssertEqual(flow.state, .completed)
        let sent = flow.webSocketMessages.filter { $0.direction == .clientToServer }.map { String(decoding: $0.payload, as: UTF8.self) }
        let received = flow.webSocketMessages.filter { $0.direction == .serverToClient }.map { String(decoding: $0.payload, as: UTF8.self) }
        XCTAssertEqual(sent, ["ping1", "ping2"])
        XCTAssertEqual(received, ["ping1", "ping2"])

        do { try await engine.composeWebSocket(url: XCTUnwrap(URL(string: "http://x/")), messages: []); XCTFail("expected an error") } catch {}
    }

    func testPreviewerScriptsDecodeBinaryBodiesAndReportFailures() async throws {
        let engine = try engine()
        try engine.settings.update {
            $0.previewers = RuleSet(isEnabled: true, rules: [
                PreviewerRule(name: "Base64", matching: MatchingRule(pattern: "*/b64"), source: "function preview(m) { return atob(m.bodyBase64).toUpperCase(); }"),
                PreviewerRule(name: "Summary", matching: MatchingRule(pattern: "*/b64"), source: "function preview(m) { return { status: m.status, size: m.bodyBase64.length }; }"),
                PreviewerRule(name: "Broken", matching: MatchingRule(pattern: "*/b64"), source: "function preview(m) { throw new Error('boom'); }"),
                PreviewerRule(name: "Elsewhere", matching: MatchingRule(pattern: "*/other"), source: "function preview(m) { return 'no'; }"),
            ])
        }
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/b64"))
        flow.response = ResponseRecord(status: 200, body: Data("hello".utf8))
        let outputs = await engine.previews(for: flow)
        XCTAssertEqual(outputs.map(\.name), ["Base64", "Summary", "Broken"])
        XCTAssertEqual(outputs[0].text, "HELLO")
        XCTAssertTrue(outputs[1].text.contains("\"status\" : 200") && outputs[1].text.contains("\"size\" : 8"), outputs[1].text)
        XCTAssertTrue(outputs[2].text.hasPrefix("Previewer failed") && outputs[2].text.contains("boom"), outputs[2].text)
    }

    func testSideBySideDiffPairsRemovalsWithAdditions() {
        let rows = TextDiff.sideBySide(TextDiff.lines(from: "a\nb\nc", to: "a\nx\ny\nc"))
        XCTAssertEqual(rows.map { [$0.left?.text, $0.right?.text] }, [["a", "a"], ["b", "x"], [nil, "y"], ["c", "c"]])
        XCTAssertEqual(rows[1].left?.kind, .removed); XCTAssertEqual(rows[1].right?.kind, .added)
    }

    func testRequestTimingAndUpstreamVersionAreRecordedAndExported() async throws {
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }
        _ = try await harness.get("/timing")
        let flow = try XCTUnwrap(harness.engine.store.all.first)
        XCTAssertEqual(flow.upstreamHTTPVersion, "HTTP/1.1")
        let firstByte = try XCTUnwrap(flow.timeToFirstByte)
        XCTAssertTrue(firstByte >= 0 && firstByte <= (flow.duration ?? 0) + 0.001)

        let entry = try XCTUnwrap(try ((JSONSerialization.jsonObject(with: HAR.export([flow])) as? [String: Any])?["log"] as? [String: Any])?["entries"] as? [[String: Any]]).first
        XCTAssertEqual((entry?["response"] as? [String: Any])?["httpVersion"] as? String, "HTTP/1.1")
        XCTAssertEqual((entry?["timings"] as? [String: Any])?["wait"] as? Double ?? -1, firstByte * 1000, accuracy: 0.5)
    }
}

final class FieldsAndNetworkTests: XCTestCase {
    func testQueryUrlencodedAndMultipartFields() {
        let form = RequestRecord(
            method: "POST",
            scheme: "https",
            host: "a.com",
            port: 443,
            path: "/submit?debug=1&q=a%20b",
            headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
            body: Data("name=Ada+L&city=Z%C3%BCrich".utf8)
        )
        // `+` in a urlencoded body means a space; URLComponents leaves it, so the viewer shows the raw text for that case.
        XCTAssertEqual(
            FormFields.parse(form).map { "\($0.source.rawValue):\($0.name)=\($0.value)" },
            ["query:debug=1", "query:q=a b", "form:name=Ada+L", "form:city=Zürich"]
        )

        let body = "--XX\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n--XX\r\nContent-Disposition: form-data; name=\"upload\"; filename=\"a.png\"\r\nContent-Type: image/png\r\n\r\n\u{1}\u{2}\u{3}\r\n--XX--\r\n"
        let multipart = RequestRecord(
            method: "POST",
            scheme: "https",
            host: "a.com",
            port: 443,
            path: "/u",
            headers: [Header("Content-Type", "multipart/form-data; boundary=XX")],
            body: Data(body.utf8)
        )
        let fields = FormFields.parse(multipart)
        XCTAssertEqual(fields.map(\.name), ["title", "upload"])
        XCTAssertEqual(fields[0].value, "hello")
        XCTAssertEqual(fields[1].filename, "a.png")
        XCTAssertEqual(fields[1].value, "image/png, 3 bytes")
        XCTAssertTrue(FormFields.parse(RequestRecord(method: "GET", scheme: "https", host: "a", port: 443, path: "/")).isEmpty)
    }

    func testLocalNetworkAddressesAreRealLANIPv4() {
        let addresses = LocalNetwork.ipv4Addresses()
        XCTAssertTrue(addresses.allSatisfy { $0.ip != "127.0.0.1" && !$0.ip.hasPrefix("169.254.") && $0.ip.split(separator: ".").count == 4 })
    }
}

final class JQAndConnectionTests: XCTestCase {
    func testJQRunsRealFiltersAndRefusesOptionInjection() throws {
        guard JQ.executable != nil else { throw XCTSkip("jq is not installed") }
        let json = Data(#"{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Linus"}]}"#.utf8)
        XCTAssertEqual(JQ.run(".users[] | .name", on: json)?.split(separator: "\n").map(String.init), ["\"Ada\"", "\"Linus\""])
        XCTAssertEqual(JQ.run("[.users[].id] | add", on: json)?.trimmingCharacters(in: .whitespacesAndNewlines), "3")
        XCTAssertNil(JQ.run(".users[", on: json), "invalid program")
        XCTAssertNil(JQ.run("--help", on: json), "must not be read as an option")
        XCTAssertEqual(JQ.run("$ENV | length", on: json)?.trimmingCharacters(in: .whitespacesAndNewlines), "0", "environment is not exposed")
        XCTAssertTrue(JQ.looksLikeJQ(".a") && JQ.looksLikeJQ("map(.x)") && !JQ.looksLikeJQ("users[0].name") && !JQ.looksLikeJQ("email"))
    }

    func testClientTLSVersionAndProtocolAreRecordedOnDecryptedConnections() async throws {
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }

        let script = """
        import socket, ssl
        s = socket.create_connection(("127.0.0.1", \(harness.proxyPort)), timeout=10)
        s.sendall(b"CONNECT upstream.test:443 HTTP/1.1\\r\\nHost: upstream.test:443\\r\\n\\r\\n"); s.recv(4096)
        ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
        t = ctx.wrap_socket(s, server_hostname="upstream.test")
        t.sendall(b"GET /tls HTTP/1.1\\r\\nHost: upstream.test\\r\\nConnection: close\\r\\n\\r\\n")
        t.settimeout(10)
        try: t.recv(4096)
        except Exception: pass
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-c", script]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw XCTSkip("python3 unavailable") }
        process.waitUntilExit()

        for _ in 0 ..< 40 where harness.engine.store.all.first?.clientTLS == nil {
            try await Task.sleep(for: .milliseconds(50))
        }
        let flow = try XCTUnwrap(harness.engine.store.all.first)
        XCTAssertEqual(flow.request.path, "/tls")
        let tls = try XCTUnwrap(flow.clientTLS)
        XCTAssertTrue(tls.hasPrefix("TLS 1.") && tls.hasSuffix("http/1.1"), tls)
    }
}

final class SystemProxyRestoreTests: XCTestCase {
    /// A fake `networksetup` with one service that already has a web proxy of its own.
    private final class FakeNetwork: @unchecked Sendable {
        let lock = NSLock()
        var calls: [[String]] = []
        func run(_ arguments: [String]) -> String {
            lock.withLock { calls.append(arguments) }
            switch arguments.first {
            case "-listallnetworkservices": return "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n"
            case "-getwebproxy": return "Enabled: Yes\nServer: corp-proxy.local\nPort: 3128\nAuthenticated Proxy Enabled: 0\n"
            case "-getsecurewebproxy": return "Enabled: No\nServer: 0.0.0.0\nPort: 0\nAuthenticated Proxy Enabled: 0\n"
            default: return ""
            }
        }
    }

    func testDisableRestoresTheUsersOwnProxyInsteadOfSwitchingItOff() throws {
        let backup = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-sp-\(UUID().uuidString).json")
        let network = FakeNetwork()
        let proxy = SystemProxy(run: { network.run($0) }, backupURL: backup)

        try proxy.enable(port: 9090)
        try proxy.enable(port: 9090) // a second enable must keep the real original
        let saved = try JSONDecoder().decode([String: SystemProxy.Original].self, from: Data(contentsOf: backup))
        XCTAssertEqual(saved["Wi-Fi"]?.web, .init(enabled: true, server: "corp-proxy.local", port: 3128))
        XCTAssertEqual(saved["Wi-Fi"]?.secure.enabled, false)

        network.calls.removeAll()
        try proxy.disable()
        XCTAssertTrue(network.calls.contains(["-setwebproxy", "Wi-Fi", "corp-proxy.local", "3128"]))
        XCTAssertTrue(network.calls.contains(["-setwebproxystate", "Wi-Fi", "on"]), "the user's proxy was on and stays on")
        XCTAssertTrue(network.calls.contains(["-setsecurewebproxystate", "Wi-Fi", "off"]))
        XCTAssertFalse(network.calls.contains { $0.first == "-setsecurewebproxy" }, "an empty original secure proxy has no host to write back")
        XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path), "backup is consumed")

        // Without a backup (Watcher never enabled it) disabling just switches the proxies off.
        network.calls.removeAll()
        try proxy.disable()
        XCTAssertTrue(network.calls.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    }

    func testParseHandlesMissingFields() {
        XCTAssertEqual(SystemProxy.parse("Enabled: Yes\nServer: h\nPort: 8080\n"), .init(enabled: true, server: "h", port: 8080))
        XCTAssertEqual(SystemProxy.parse(""), .init(enabled: false, server: "", port: 0))
    }
}

final class RuleFolderTests: XCTestCase {
    func testFoldersGroupRulesAndSwitchThemTogether() {
        var set = RuleSet<BlockRule>(isEnabled: true, rules: [
            BlockRule(name: "a", matching: MatchingRule(pattern: "a")),
            BlockRule(name: "b", matching: MatchingRule(pattern: "b")),
            BlockRule(name: "c", matching: MatchingRule(pattern: "c")),
        ])
        set.rules[0].folder = "Ads"; set.rules[1].folder = "Ads"; set.rules[2].folder = "Tracking"
        XCTAssertEqual(set.folders, ["Ads", "Tracking"])

        set.setFolder("Ads", enabled: false)
        XCTAssertEqual(set.rules.map(\.isEnabled), [false, false, true])
        XCTAssertEqual(set.active.map(\.name), ["c"], "disabled folder rules no longer take effect")
        set.setFolder("Ads", enabled: true)
        XCTAssertEqual(set.active.count, 3)
        set.setFolder("Missing", enabled: false)
        XCTAssertEqual(set.active.count, 3, "an unknown folder changes nothing")
    }

    func testFolderSurvivesSavingAndOlderRulesLoadWithoutOne() throws {
        let rule: MapLocalRule = try {
            var rule = MapLocalRule(name: "m", matching: MatchingRule(pattern: "*/m"), source: .file("/x"))
            rule.folder = "Checkout"
            return rule
        }()
        let decoded = try JSONDecoder().decode(MapLocalRule.self, from: JSONEncoder().encode(rule))
        XCTAssertEqual(decoded.folder, "Checkout")

        let old = try JSONDecoder().decode(BlockRule.self, from: Data(#"{"name":"x","isEnabled":true,"hidesRequest":false,"matching":{"pattern":"*","mode":"wildcard","methods":[],"includeSubpaths":false}}"#.utf8))
        XCTAssertNil(old.folder)
    }

    func testEveryRuleTypeCanBeFiled() {
        func filed(_ rule: some ToolRule) -> String? {
            var copy = rule; copy.folder = "F"; return copy.folder
        }
        XCTAssertEqual(filed(AllowRule(matching: MatchingRule())), "F")
        XCTAssertEqual(filed(ScriptRule(matching: MatchingRule())), "F")
        XCTAssertEqual(filed(DNSSpoofRule(host: "a", address: "b")), "F")
        XCTAssertEqual(filed(ReverseProxyRule(localPort: 10000, remoteHost: "a")), "F")
        XCTAssertEqual(filed(CustomCertificateRule(host: "a", role: .server, p12Path: "")), "F")
        XCTAssertEqual(filed(ProtobufRule(matching: MatchingRule())), "F")
        XCTAssertEqual(filed(PreviewerRule(matching: MatchingRule())), "F")
    }
}

/// Advanced settings: access control, HTTP/2, IPv6, TLS key log, certificate validity and the rest.
final class AdvancedSettingsTests: XCTestCase {
    func testAccessControlAllowsLoopbackAlwaysAndOthersOnlyWhenListed() {
        let open = AccessControlSettings()
        XCTAssertTrue(open.allows("192.168.1.50"), "switched off: everyone who can connect is allowed")
        let restricted = AccessControlSettings(isEnabled: true, allowedAddresses: ["192.168.1.*", "10.0.0.7"])
        XCTAssertTrue(restricted.allows("127.0.0.1") && restricted.allows("::1"))
        XCTAssertTrue(restricted.allows("192.168.1.50") && restricted.allows("10.0.0.7"))
        XCTAssertFalse(restricted.allows("192.168.2.50"))
        XCTAssertFalse(restricted.allows("8.8.8.8"))
        XCTAssertFalse(restricted.allows(nil), "an unknown peer is refused")
        XCTAssertFalse(AccessControlSettings(isEnabled: true).allows("192.168.1.2"), "an empty list admits only this Mac")
    }

    func testRedactionHidesSecretsOnlyInSecretHeaders() {
        let headers = Redaction.redact([Header("Authorization", "Bearer abc"), Header("cookie", "sid=1"), Header("Accept", "*/*"), Header("X-Api-Key", "k")])
        XCTAssertEqual(headers.map(\.value), ["[redacted]", "[redacted]", "*/*", "[redacted]"])
        XCTAssertEqual(headers.map(\.name), ["Authorization", "cookie", "Accept", "X-Api-Key"])
    }

    func testAppleTrafficAndCURLProxyAndNewDefaults() throws {
        XCTAssertTrue(AppleTraffic.isApple("api.apple.com") && AppleTraffic.isApple("p25-ckdatabase.icloud.com") && AppleTraffic.isApple("apple.com"))
        XCTAssertFalse(AppleTraffic.isApple("example.com") || AppleTraffic.isApple("notapple.com") || AppleTraffic.isApple("apple.com.evil.test"))
        let request = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/")
        XCTAssertTrue(CodeGenerator.generate(request, as: .curl, proxy: "http://127.0.0.1:9090").contains("-x 'http://127.0.0.1:9090'"))
        XCTAssertFalse(CodeGenerator.generate(request, as: .curl).contains(" -x "))
        let defaults = try JSONDecoder().decode(WatcherSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.preferHTTP2 && defaults.mcpRedaction)
        XCTAssertFalse(defaults.listenOnIPv6 || defaults.autoIgnoreSSLPinning || defaults.hideAppleTraffic || defaults.autoSystemProxy)
        XCTAssertEqual([defaults.leafCertificateValidityDays, defaults.maxFlows, defaults.composeTimeoutSeconds], [365, 0, 60])
    }

    func testLeafCertificateValidityFollowsTheSettingAndStaysUnderApplesLimit() throws {
        let ca = try CertificateAuthority(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-ca-\(UUID().uuidString)"))
        func days() throws -> Double {
            let leaf = try ca.leafCertificate(for: "a.test")
            return (leaf.notValidAfter.timeIntervalSince(leaf.notValidBefore) - 3600) / 86400
        }
        ca.setLeafValidity(days: 30); XCTAssertEqual(try days(), 30, accuracy: 0.1)
        ca.setLeafValidity(days: 9999); XCTAssertEqual(try days(), 825, accuracy: 0.1)
        ca.setLeafValidity(days: 0); XCTAssertEqual(try days(), 1, accuracy: 0.1)
    }

    func testPausedRecordingAndSessionLimit() async throws {
        let harness = try Harness()
        try await harness.start { $0.maxFlows = 3 }
        defer { Task { await harness.stop() } }

        harness.engine.isRecording = false
        let paused = try await harness.get("/paused")
        XCTAssertEqual(paused.status, 200, "traffic still flows while recording is paused")
        XCTAssertTrue(harness.engine.store.all.isEmpty)

        harness.engine.isRecording = true
        for n in 1 ... 5 {
            _ = try await harness.get("/r\(n)")
        }
        XCTAssertEqual(harness.engine.store.all.map(\.request.path), ["/r3", "/r4", "/r5"], "only the newest three are kept")
    }

    func testMarkerHeaderNamesTheToolsThatTouchedTheResponse() async throws {
        let harness = try Harness()
        try await harness.start { $0.noCaching = true; $0.markModifiedTraffic = true }
        defer { Task { await harness.stop() } }
        let marked = try await harness.getWithHeaders("/m")
        XCTAssertEqual(marked.headers["x-watcher-applied"], "No Caching")
        try await harness.reconfigure { $0.markModifiedTraffic = false }
        let unmarked = try await harness.getWithHeaders("/m")
        XCTAssertNil(unmarked.headers["x-watcher-applied"])
    }

    func testComposeTimeoutAnswersWith502WhenTheServerStaysSilent() async throws {
        let harness = try Harness(), silent = SilentOrigin()
        try await silent.start(); try await harness.start()
        defer { Task { await harness.stop(); await silent.stop() } }
        let started = Date()
        let response = await harness.engine.send(RequestRecord(method: "GET", scheme: "http", host: "127.0.0.1", port: silent.port, path: "/"), timeout: 1)
        XCTAssertEqual(response.status, 502)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }

    func testMCPOutputRedactsSecretsUnlessSwitchedOff() async throws {
        let engine = try WatcherEngine(directory: FileManager.default.temporaryDirectory.appendingPathComponent("watcher-test-\(UUID().uuidString)"))
        var request = RequestRecord(method: "GET", scheme: "https", host: "a.com", port: 443, path: "/", headers: [Header("Authorization", "Bearer SECRET-TOKEN")])
        request.clientApp = nil
        var flow = Flow(sequence: 1, request: request)
        flow.response = ResponseRecord(status: 200, headers: [Header("Set-Cookie", "sid=SECRET-COOKIE")])
        engine.store.load([flow])
        let server = MCPServer(engine: engine)

        func text(_ tool: String) async throws -> String {
            let line = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"\#(tool)","arguments":{"sequence":"1"}}}"#)
            let reply = try XCTUnwrap(line)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
            return (((object["result"] as? [String: Any])?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        }
        for tool in ["get_flow_detail", "export_flow_curl"] {
            let shown = try await text(tool)
            XCTAssertFalse(shown.contains("SECRET"), "\(tool): \(shown)")
            XCTAssertTrue(shown.contains("[redacted]"))
        }
        try engine.settings.update { $0.mcpRedaction = false }
        let plain = try await text("get_flow_detail")
        XCTAssertTrue(plain.contains("SECRET-TOKEN"))
    }
}

final class TLSBehaviourTests: XCTestCase {
    func testHTTP2IsOfferedOnlyWhenPreferred() async throws {
        try XCTSkipUnless(ExternalTool.python3.isAvailable, "python3 unavailable")
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }
        func negotiated() throws -> String {
            try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "alpn.test", verify: false, alpn: ["h2", "http/1.1"]) + "\nprint(t.selected_alpn_protocol() if t else 'failed')").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        XCTAssertEqual(try negotiated(), "h2")
        try await harness.reconfigure { $0.preferHTTP2 = false }
        XCTAssertEqual(try negotiated(), "http/1.1")
    }

    func testAClientThatRejectsTheCertificateGetsItsHostExcludedWhenAutoIgnoreIsOn() async throws {
        try XCTSkipUnless(ExternalTool.python3.isAvailable, "python3 unavailable")
        let harness = try Harness()
        try await harness.start { $0.autoIgnoreSSLPinning = true }
        defer { Task { await harness.stop() } }
        let output = try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "pinned.test", verify: true) + "\nprint('rejected' if err else 'accepted')")
        XCTAssertTrue(output.contains("rejected"), output)
        for _ in 0 ..< 60 where !harness.engine.settings.value.sslProxying.exclude.contains("pinned.test") {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(harness.engine.settings.value.sslProxying.exclude, ["pinned.test"])
    }

    func testRejectedHandshakeIsIgnoredWhenAutoIgnoreIsOff() async throws {
        try XCTSkipUnless(ExternalTool.python3.isAvailable, "python3 unavailable")
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }
        _ = try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "pinned.test", verify: true) + "\nprint(1)")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertTrue(harness.engine.settings.value.sslProxying.exclude.isEmpty)
    }

    func testTLSKeyLogReceivesSessionSecretsInANonPublicFile() async throws {
        try XCTSkipUnless(ExternalTool.python3.isAvailable, "python3 unavailable")
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-keylog-\(UUID().uuidString).txt")
        let harness = try Harness()
        try await harness.start { $0.tlsKeyLogFile = log.path }
        defer { Task { await harness.stop() } }
        _ = try runPython(pythonTLSViaProxy(port: harness.proxyPort, host: "keys.test", verify: false) + "\nprint(t.version() if t else 'failed')")
        for _ in 0 ..< 40 where (try? String(contentsOf: log, encoding: .utf8))?.isEmpty != false {
            try await Task.sleep(for: .milliseconds(50))
        }
        let content = try String(contentsOf: log, encoding: .utf8)
        XCTAssertTrue(content.contains("CLIENT_RANDOM") || content.contains("TRAFFIC_SECRET"), content)
        let permissions = try FileManager.default.attributesOfItem(atPath: log.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)
    }
}

/// Runs against a real Charles Proxy when one is installed (skipped otherwise).
final class RealCharlesTests: XCTestCase {
    private func requireCharles() throws {
        guard FileManager.default.isExecutableFile(atPath: CharlesConverter.defaultExecutable.path) else { throw XCTSkip("Charles is not installed") }
    }

    private func convert(_ input: URL, to output: URL) throws {
        let process = Process()
        process.executableURL = CharlesConverter.defaultExecutable
        process.arguments = ["convert", input.path, output.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
    }

    func testBinarySessionsFromARealCharlesAreReadBack() async throws {
        try requireCharles()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-charles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var post = Flow(sequence: 2, request: RequestRecord(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            path: "/v1/login?x=1",
            headers: [Header("Content-Type", "application/json")],
            body: Data(#"{"user":"ada"}"#.utf8)
        ))
        post.response = ResponseRecord(status: 401, headers: [Header("Content-Type", "application/json")], body: Data(#"{"error":"nope"}"#.utf8))
        post.state = .completed; post.duration = 0.2
        var get = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/"))
        get.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "text/html")], body: Data("<h1>hi</h1>".utf8))
        get.state = .completed; get.duration = 0.1

        let har = directory.appendingPathComponent("in.har")
        try HAR.export([get, post]).write(to: har)
        // Charles itself writes the binary formats.
        let chls = directory.appendingPathComponent("session.chls"), chlz = directory.appendingPathComponent("session.chlz")
        try convert(har, to: chls)
        try convert(chls, to: chlz)

        for session in [chls, chlz] {
            let flows = try await CharlesConverter.flows(from: session)
            XCTAssertEqual(flows.count, 2, session.lastPathComponent)
            let byPath = Dictionary(uniqueKeysWithValues: flows.map { ($0.request.path, $0) })
            XCTAssertEqual(byPath["/"]?.response?.status, 200, session.lastPathComponent)
            XCTAssertEqual(byPath["/v1/login?x=1"]?.request.method, "POST")
            XCTAssertEqual(byPath["/v1/login?x=1"]?.response?.status, 401)
            XCTAssertEqual(byPath["/v1/login?x=1"]?.request.body, Data(#"{"user":"ada"}"#.utf8))
            XCTAssertEqual(String(decoding: byPath["/"]?.response?.body ?? Data(), as: UTF8.self), "<h1>hi</h1>")
        }
    }

    func testRealChlsjFilesImportWithDefaultPortsAndOffsetTimestamps() throws {
        try requireCharles()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-charles-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "example.com", port: 443, path: "/a?b=1"))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "text/plain")], body: Data("hello".utf8))
        flow.state = .completed; flow.duration = 0.25
        let har = directory.appendingPathComponent("in.har"), chlsj = directory.appendingPathComponent("real.chlsj")
        try HAR.export([flow]).write(to: har)
        try convert(har, to: chlsj)

        let imported = try CharlesSession.flows(from: Data(contentsOf: chlsj)).filter { $0.request.method != "CONNECT" }
        let first = try XCTUnwrap(imported.first)
        XCTAssertEqual(first.request.url, "https://example.com/a?b=1", "actualPort -1 must fall back to 443")
        XCTAssertEqual(first.response?.status, 200)
        XCTAssertEqual(String(decoding: first.response?.body ?? Data(), as: UTF8.self), "hello")
        XCTAssertNotEqual(first.startedAt.timeIntervalSince1970, 0)
    }

    func testAGarbageFileIsReportedNotSilentlyIgnored() async throws {
        try requireCharles()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-garbage-\(UUID().uuidString).chls")
        try Data("this is not a charles session".utf8).write(to: file)
        do { _ = try await CharlesConverter.flows(from: file); XCTFail("expected a conversion error") }
        catch let error as CharlesConverter.ConversionError { XCTAssertTrue("\(error)".contains("could not convert"), "\(error)") }
    }
}

/// Settings exactly as Charles Proxy 5.2.2 wrote them after loading and re-saving a configuration (`charles --headless --config`),
/// so every tag, order and omitted default below is Charles' own.
final class CharlesSettingsTests: XCTestCase {
    private let realExport = """
    <?xml version='1.0' encoding='UTF-8' ?>
    <?charles serialisation-version='2.0' ?>
    <configuration>
      <toolConfiguration>
        <configs>
          <entry>
            <string>Breakpoints</string>
            <breakpoints>
              <toolEnabled>true</toolEnabled>
              <breakpoints>
                <breakpoint>
                  <location>
                    <protocol>https</protocol>
                    <host>login.example.com</host>
                    <port>443</port>
                    <path>/token</path>
                  </location>
                  <method>POST</method>
                  <request>true</request>
                </breakpoint>
              </breakpoints>
            </breakpoints>
          </entry>
          <entry>
            <string>Reverse Proxies</string>
            <reverseProxies>
              <reverseProxies>
                <reverseProxy>
                  <sourcePort>18888</sourcePort>
                  <destPort>443</destPort>
                  <destHost>api.example.com</destHost>
                  <preserveHostHeader>true</preserveHostHeader>
                </reverseProxy>
              </reverseProxies>
            </reverseProxies>
          </entry>
          <entry>
            <string>Block List</string>
            <blacklist>
              <locations>
                <locationPatterns>
                  <locationMatch>
                    <location>
                      <protocol>https</protocol>
                      <host>ads.example.com</host>
                      <port>443</port>
                      <path>/*</path>
                    </location>
                  </locationMatch>
                  <locationMatch>
                    <enabled>false</enabled>
                    <location>
                      <protocol>https</protocol>
                      <host>off.example.com</host>
                      <port>443</port>
                    </location>
                  </locationMatch>
                </locationPatterns>
              </locations>
              <toolEnabled>true</toolEnabled>
            </blacklist>
          </entry>
          <entry>
            <string>Map Remote</string>
            <map>
              <toolEnabled>true</toolEnabled>
              <mappings>
                <mapMapping>
                  <sourceLocation>
                    <protocol>https</protocol>
                    <host>old.example.com</host>
                    <port>443</port>
                    <path>/v1/*</path>
                  </sourceLocation>
                  <destLocation>
                    <protocol>https</protocol>
                    <host>new.example.com</host>
                    <port>8443</port>
                    <path>/v2/x</path>
                    <query>a=1</query>
                  </destLocation>
                  <preserveHostHeader>true</preserveHostHeader>
                </mapMapping>
              </mappings>
            </map>
          </entry>
          <entry>
            <string>Map Local</string>
            <mapLocal>
              <toolEnabled>true</toolEnabled>
              <mappings>
                <mapLocalMapping>
                  <sourceLocation>
                    <protocol>https</protocol>
                    <host>api.example.com</host>
                    <port>443</port>
                    <path>/v1/users</path>
                  </sourceLocation>
                  <dest>/tmp/users.json</dest>
                </mapLocalMapping>
                <mapLocalMapping>
                  <sourceLocation>
                    <host>static.example.com</host>
                    <path>/assets/*</path>
                  </sourceLocation>
                  <dest>/tmp</dest>
                  <enabled>false</enabled>
                </mapLocalMapping>
              </mappings>
            </mapLocal>
          </entry>
          <entry>
            <string>Allow List</string>
            <whitelist>
              <locations>
                <locationPatterns>
                  <locationMatch>
                    <location>
                      <protocol>http</protocol>
                      <host>*.corp.test</host>
                      <port>8080</port>
                    </location>
                  </locationMatch>
                </locationPatterns>
              </locations>
            </whitelist>
          </entry>
          <entry>
            <string>No Caching</string>
            <selectedHostsTool />
          </entry>
          <entry>
            <string>DNS Spoofing</string>
            <dnsSpoofing>
              <toolEnabled>true</toolEnabled>
              <spoofs>
                <dnsSpoof>
                  <name>dev.example.com</name>
                  <address>127.0.0.1</address>
                </dnsSpoof>
              </spoofs>
            </dnsSpoofing>
          </entry>
        </configs>
      </toolConfiguration>
    </configuration>
    """

    private func request(_ host: String, _ path: String, method: String = "GET", scheme: String = "https", port: Int = 443) -> RequestRecord {
        .fixture(method: method, scheme: scheme, host: host, port: port, path: path)
    }

    func testBlockAndAllowListsKeepPerEntryFlagsAndToolSwitch() throws {
        let settings = try CharlesSettings.importSettings(from: Data(realExport.utf8))
        XCTAssertTrue(settings.blockList.isEnabled)
        XCTAssertEqual(settings.blockList.rules.map(\.isEnabled), [true, false], "the second match carries enabled=false")
        let ads = try XCTUnwrap(settings.blockList.rules.first).matching.compile()
        XCTAssertTrue(ads.matches(request("ads.example.com", "/banner.gif")), "Charles writes <port>443</port>; it must not break matching")
        XCTAssertFalse(ads.matches(request("example.com", "/")))

        XCTAssertFalse(settings.allowList.isEnabled, "Charles omits toolEnabled when it is false")
        let corp = try XCTUnwrap(settings.allowList.rules.first).matching.compile()
        XCTAssertTrue(corp.matches(request("api.corp.test", "/x", scheme: "http", port: 8080)))
        XCTAssertFalse(corp.matches(request("api.corp.test", "/x", scheme: "http", port: 80)), "a non-default port stays in the pattern")
    }

    func testMapLocalFileAndDirectoryAndDisabledEntry() throws {
        let local = try CharlesSettings.importSettings(from: Data(realExport.utf8)).mapLocal
        XCTAssertTrue(local.isEnabled)
        XCTAssertEqual(local.rules.map(\.source), [.file("/tmp/users.json"), .directory("/tmp")], "an existing folder becomes a directory mapping")
        XCTAssertEqual(local.rules.map(\.isEnabled), [true, false])
        XCTAssertTrue(local.rules[0].matching.compile().matches(request("api.example.com", "/v1/users")))
    }

    func testMapRemoteKeepsDestinationAndPreserveHostHeader() throws {
        let remote = try XCTUnwrap(CharlesSettings.importSettings(from: Data(realExport.utf8)).mapRemote.rules.first)
        XCTAssertEqual(remote.destination, .init(scheme: "https", host: "new.example.com", port: 8443, path: "/v2/x", query: "a=1"))
        XCTAssertTrue(remote.preserveHostHeader)
        XCTAssertTrue(remote.matching.compile().matches(request("old.example.com", "/v1/things")))
    }

    func testBreakpointsDnsAndReverseProxy() throws {
        let settings = try CharlesSettings.importSettings(from: Data(realExport.utf8))
        let breakpoint = try XCTUnwrap(settings.breakpoints.rules.first)
        XCTAssertTrue(breakpoint.onRequest); XCTAssertFalse(breakpoint.onResponse, "Charles omits response=false")
        XCTAssertTrue(breakpoint.matching.compile().matches(request("login.example.com", "/token", method: "POST")))
        XCTAssertFalse(breakpoint.matching.compile().matches(request("login.example.com", "/token")), "method=POST is kept")

        XCTAssertEqual(settings.dnsSpoofing.rules, [DNSSpoofRule(host: "dev.example.com", address: "127.0.0.1")])

        let reverse = try XCTUnwrap(settings.reverseProxy.rules.first)
        XCTAssertEqual([reverse.localPort, reverse.remotePort], [18888, 443])
        XCTAssertEqual(reverse.remoteHost, "api.example.com")
        XCTAssertTrue(reverse.preserveHost && reverse.forceTLS)
    }

    func testImportingOverToolRulesKeepsEverythingElse() throws {
        var current = WatcherSettings()
        current.port = 7777; current.socks = SocksSettings(isEnabled: true, port: 9999); current.sslProxying.exclude = ["pinned.test"]
        current.blockList = RuleSet(isEnabled: true, rules: [BlockRule(name: "old", matching: MatchingRule(pattern: "old"))])
        let merged = try current.replacingToolRules(with: CharlesSettings.importSettings(from: Data(realExport.utf8)))
        XCTAssertEqual(merged.blockList.rules.map(\.name), ["Charles", "Charles"], "the tool rules are replaced")
        XCTAssertEqual([merged.port, merged.socks.port], [7777, 9999])
        XCTAssertEqual(merged.sslProxying.exclude, ["pinned.test"])
    }

    func testEmptyReverseProxyToolStaysOff() throws {
        let empty = try CharlesSettings.importSettings(from: Data("<configuration><toolConfiguration><configs><entry><string>Reverse Proxies</string><reverseProxies /></entry></configs></toolConfiguration></configuration>".utf8))
        XCTAssertFalse(empty.reverseProxy.isEnabled)
    }

    func testEmptyDefaultsAndNonXML() throws {
        let empty = try CharlesSettings.importSettings(from: Data("<configuration><toolConfiguration><configs><entry><string>Block List</string><blacklist /></entry></configs></toolConfiguration></configuration>".utf8))
        XCTAssertFalse(empty.blockList.isEnabled); XCTAssertTrue(empty.blockList.rules.isEmpty)
        XCTAssertThrowsError(try CharlesSettings.importSettings(from: Data("not xml <<<".utf8)))
    }

    func testMapRemoteToolHonoursPreserveHostHeader() async {
        var rule = MapRemoteRule(matching: MatchingRule(pattern: "*"), destination: .init(host: "new.test"))
        var request = RequestRecord(method: "GET", scheme: "https", host: "old.test", port: 443, path: "/", headers: [Header("Host", "old.test")])
        _ = await MapRemoteTool(rules: [rule]).intercept(request: &request)
        XCTAssertEqual(request.headers.value(for: "host"), "new.test")
        rule.preserveHostHeader = true
        var kept = RequestRecord(method: "GET", scheme: "https", host: "old.test", port: 443, path: "/", headers: [Header("Host", "old.test")])
        _ = await MapRemoteTool(rules: [rule]).intercept(request: &kept)
        XCTAssertEqual(kept.host, "new.test"); XCTAssertEqual(kept.headers.value(for: "host"), "old.test")
    }
}
