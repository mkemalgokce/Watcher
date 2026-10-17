@testable import WatcherCore
import WatcherTestSupport
import XCTest

final class FilterTests: XCTestCase {
    private func flow(
        _ method: String = "GET",
        host: String = "api.example.com",
        path: String = "/a",
        status: Int? = 200,
        type: String? = "application/json",
        body: String = "",
        app: String? = nil
    ) -> Flow {
        .fixture(
            request: .fixture(method: method, host: host, path: path, clientApp: app),
            response: status.map { status in
                .fixture(
                    status: status,
                    headers: type.map { [Header("Content-Type", $0)] } ?? [],
                    body: Data(body.utf8)
                )
            }
        )
    }

    func testEmptyFilterIsInactiveAndKeepsEverything() {
        let filter = FlowFilter()
        XCTAssertFalse(filter.isActive)
        XCTAssertEqual(filter.apply(to: [flow(), flow(status: nil)]).count, 2)
    }

    func testQuickToggles() {
        var f = FlowFilter(); f.methods = ["POST"]
        XCTAssertFalse(f.matches(flow())); XCTAssertTrue(f.matches(flow("post")))
        f.reset(); f.statusClasses = [4, 5]
        XCTAssertTrue(f.matches(flow(status: 404))); XCTAssertFalse(f.matches(flow(status: 200)))
        f.reset(); f.errorsOnly = true
        XCTAssertTrue(f.matches(flow(status: nil))); XCTAssertTrue(f.matches(flow(status: 500))); XCTAssertFalse(f.matches(flow()))
        f.reset(); f.contentKinds = [.image]
        XCTAssertTrue(f.matches(flow(type: "image/png"))); XCTAssertFalse(f.matches(flow()))
        f.reset(); f.starredOnly = true
        var starred = flow(); starred.isStarred = true
        XCTAssertTrue(f.matches(starred)); XCTAssertFalse(f.matches(flow()))
    }

    func testTextScopes() {
        var f = FlowFilter(); f.text = "needle"
        XCTAssertFalse(f.matches(flow(path: "/x", body: "needle")))
        f.scope = .body; XCTAssertTrue(f.matches(flow(body: "a NEEDLE b")))
        f.scope = .url; XCTAssertTrue(f.matches(flow(path: "/needle")))
        f.scope = .all
        var commented = flow(); commented.comment = "needle here"
        XCTAssertTrue(f.matches(commented)); XCTAssertFalse(f.matches(flow()))
    }

    func testSidebarSelectionIncludesSubdomains() {
        var f = FlowFilter(); f.host = "example.com"
        XCTAssertTrue(f.matches(flow(host: "api.example.com"))); XCTAssertTrue(f.matches(flow(host: "example.com")))
        XCTAssertFalse(f.matches(flow(host: "notexample.com")))
        f.reset(); f.app = "Safari"
        XCTAssertTrue(f.matches(flow(app: "Safari"))); XCTAssertFalse(f.matches(flow(app: "curl")))
    }

    func testGrouping() {
        let flows = [flow(host: "a.example.com"), flow(host: "b.example.com"), flow(host: "x.bbc.co.uk"), flow(host: "10.0.0.1"), flow(app: "Safari")]
        let domains = FlowGrouping.domains(flows)
        XCTAssertEqual(domains.first, FlowGroup(name: "example.com", count: 3)) // a.example.com, b.example.com + default flow's api.example.com
        XCTAssertTrue(domains.contains(FlowGroup(name: "bbc.co.uk", count: 1)))
        XCTAssertTrue(domains.contains(FlowGroup(name: "10.0.0.1", count: 1)))
        XCTAssertEqual(FlowGrouping.apps(flows), [FlowGroup(name: "Safari", count: 1)])
    }

    func testStarAndCommentPersistAndOldSessionsStillLoad() throws {
        var f = flow(); f.isStarred = true; f.comment = "check"
        let back = try SessionFile.decode(SessionFile.encode([f])).first
        XCTAssertEqual(back?.isStarred, true); XCTAssertEqual(back?.comment, "check")
        let legacy = try JSONSerialization.data(withJSONObject: ["id": UUID().uuidString, "sequence": 1, "startedAt": 0, "request": ["method": "GET", "scheme": "http", "host": "h", "port": 80, "path": "/", "headers": [], "body": ""], "state": "pending", "appliedTools": []] as [String: Any])
        XCTAssertNoThrow(try JSONDecoder().decode(Flow.self, from: legacy))
    }
}

final class CertificatePageTests: XCTestCase {
    private func page() throws -> (CertificatePage, CertificateAuthority) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID())")
        let ca = try CertificateAuthority(directory: dir)
        return (CertificatePage(authority: ca), ca)
    }

    func testRoutesAndFormats() throws {
        let (page, ca) = try page()
        XCTAssertEqual(page.response(forPath: "/").headers.value(for: "Content-Type"), "text/html; charset=utf-8")
        XCTAssertEqual(page.response(forPath: "/ca.cer").body, ca.certificateDER)
        XCTAssertEqual(String(decoding: page.response(forPath: "/ca.pem?x=1").body, as: UTF8.self), ca.certificatePEM)
        XCTAssertEqual(page.response(forPath: "/nope").status, 404)
        let profile = try XCTUnwrap(PropertyListSerialization.propertyList(from: page.mobileConfig(), format: nil) as? [String: Any])
        let content = try XCTUnwrap((profile["PayloadContent"] as? [[String: Any]])?.first)
        XCTAssertEqual(content["PayloadType"] as? String, "com.apple.security.root")
        XCTAssertEqual(content["PayloadContent"] as? Data, ca.certificateDER)
    }

    func testAddressing() {
        XCTAssertTrue(CertificatePage.isAddressed(host: "watcher.cert", port: 80, proxyPort: 9090, localAddresses: []))
        XCTAssertTrue(CertificatePage.isAddressed(host: "192.168.1.5", port: 9090, proxyPort: 9090, localAddresses: ["192.168.1.5"]))
        XCTAssertFalse(CertificatePage.isAddressed(host: "192.168.1.5", port: 80, proxyPort: 9090, localAddresses: ["192.168.1.5"]))
        XCTAssertFalse(CertificatePage.isAddressed(host: "example.com", port: 9090, proxyPort: 9090, localAddresses: ["192.168.1.5"]))
    }

    /// End to end: a device pointing at the proxy asks for http://watcher.cert/ca.cer and gets the root certificate without any upstream.
    func testServedThroughTheProxy() async throws {
        let harness = try Harness()
        try await harness.start()
        let port = harness.proxyPort
        let config = URLSessionConfiguration.ephemeral
        config.connectionProxyDictionary = ["HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port]
        let (data, response) = try await URLSession(configuration: config).data(from: XCTUnwrap(URL(string: "http://watcher.cert/ca.cer")))
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(data, harness.engine.authority.certificateDER)
        XCTAssertTrue(harness.engine.store.all.isEmpty, "the certificate page is not traffic")
        await harness.stop()
    }
}

final class DeviceSetupTests: XCTestCase {
    func testSimulatorListing() throws {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-5":[
          {"udid":"B","name":"iPhone 15","state":"Shutdown","isAvailable":true},
          {"udid":"A","name":"iPhone 15 Pro","state":"Booted","isAvailable":true},
          {"udid":"C","name":"Broken","state":"Shutdown","isAvailable":false}],
         "com.apple.CoreSimulator.SimRuntime.watchOS-10-0":[{"udid":"W","name":"Watch","state":"Shutdown"}]}}
        """
        let list = try SimulatorCertificate.simulators { arguments in
            XCTAssertEqual(arguments, ["simctl", "list", "devices", "--json"]); return json
        }
        XCTAssertEqual(list.map(\.udid), ["A", "B", "W"])
        XCTAssertEqual(list.first, .init(udid: "A", name: "iPhone 15 Pro", runtime: "iOS 17.5", isBooted: true))
    }

    func testMacTrustCommands() throws {
        let calls = LockedBox<[[String]]>([])
        let trust = MacTrust(keychain: "/k") { path, args in
            XCTAssertEqual(path, "/usr/bin/security"); calls.mutate { $0.append(args) }
            return (args[0] == "find-certificate" ? 44 : 0, "")
        }
        XCTAssertFalse(trust.isInstalled())
        try trust.install(certificate: URL(fileURLWithPath: "/tmp/ca.pem"))
        XCTAssertEqual(calls.value.last, ["add-trusted-cert", "-r", "trustRoot", "-k", "/k", "/tmp/ca.pem"])
        let failing = MacTrust(keychain: "/k") { _, _ in (1, "denied") }
        XCTAssertThrowsError(try failing.install(certificate: URL(fileURLWithPath: "/x")))
    }

    func testAndroid() throws {
        let output = """
        List of devices attached
        emulator-5554          device product:sdk model:sdk_gphone64 device:emu
        R58M123                device usb:1-1 model:Pixel_7 transport_id:2
        ZZZ                    unauthorized usb:1-2
        """
        let devices = AndroidDevice.parse(output)
        XCTAssertEqual(devices.map(\.serial), ["emulator-5554", "R58M123"])
        XCTAssertTrue(devices[0].isEmulator); XCTAssertEqual(devices[1].model, "Pixel_7")
        XCTAssertEqual(devices[0].proxyEndpoint(port: 9090, lanAddress: "1.2.3.4"), "10.0.2.2:9090")
        XCTAssertEqual(devices[1].proxyEndpoint(port: 9090, lanAddress: "1.2.3.4"), "1.2.3.4:9090")
        XCTAssertNil(devices[1].proxyEndpoint(port: 9090, lanAddress: nil))
        let calls = LockedBox<[[String]]>([])
        try devices[1].setProxy("1.2.3.4:9090") { calls.mutate($0); return "" }
        try devices[1].setProxy(nil) { calls.mutate($0); return "" }
        try devices[1].pushCertificate(URL(fileURLWithPath: "/c.pem")) { calls.mutate($0); return "" }
        XCTAssertEqual(calls.value[0].suffix(2), ["http_proxy", "1.2.3.4:9090"]); XCTAssertEqual(calls.value[1].last, ":0")
        XCTAssertEqual(calls.value[2], ["-s", "R58M123", "push", "/c.pem", "/sdcard/Download/watcher-ca.cer"])
    }
}
