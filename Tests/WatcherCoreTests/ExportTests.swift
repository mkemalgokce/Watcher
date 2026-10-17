@testable import WatcherCore
import XCTest

final class ExportTests: XCTestCase {
    private func sampleFlow() -> Flow {
        var flow = Flow(sequence: 1, request: RequestRecord(
            method: "POST", scheme: "https", host: "api.example.com", port: 443, path: "/v1/users?id=7",
            headers: [Header("Content-Type", "application/json")], body: Data(#"{"name":"it's"}"#.utf8)
        ))
        flow.response = ResponseRecord(status: 201, headers: [Header("Content-Type", "application/json")], body: Data(#"{"ok":true}"#.utf8))
        flow.state = .completed; flow.duration = 0.25
        return flow
    }

    func testHARRoundTrip() throws {
        let imported = try HAR.flows(from: HAR.export([sampleFlow()]))
        let flow = try XCTUnwrap(imported.first)
        XCTAssertEqual(flow.request.url, "https://api.example.com/v1/users?id=7")
        XCTAssertEqual(flow.request.body, Data(#"{"name":"it's"}"#.utf8))
        XCTAssertEqual(flow.response?.status, 201)
        XCTAssertEqual(flow.duration ?? 0, 0.25, accuracy: 0.001)
    }

    func testSessionRoundTripAndStoreLoad() throws {
        let flows = try SessionFile.decode(SessionFile.encode([sampleFlow()]))
        let store = FlowStore()
        store.load(flows)
        XCTAssertEqual(store.all.count, 1)
        XCTAssertEqual(store.all[0].sequence, 1)
    }

    func testCurlQuotesSingleQuotesAndDropsManagedHeaders() {
        let curl = CodeGenerator.generate(sampleFlow().request, as: .curl)
        XCTAssertTrue(curl.contains(#"--data-raw '{"name":"it'\''s"}'"#), curl)
        XCTAssertTrue(CodeGenerator.generate(sampleFlow().request, as: .swift).contains("httpMethod = \"POST\""))
    }

    func testSettingsPersistAndReload() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-\(UUID().uuidString).json")
        let first = SettingsStore(url: url)
        try first.update { $0.port = 7777; $0.blockList = RuleSet(isEnabled: true, rules: [BlockRule(matching: MatchingRule(pattern: "x"))]) }
        let second = SettingsStore(url: url)
        XCTAssertEqual(second.value.port, 7777)
        XCTAssertEqual(second.value.blockList.rules.count, 1)
    }

    func testLeafCertificatesNameTheirIssuerForStrictVerifiers() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-ca-\(UUID().uuidString)")
        let authority = try CertificateAuthority(directory: directory)
        let caIdentifier = try XCTUnwrap(authority.certificate.extensions.subjectKeyIdentifier?.keyIdentifier)
        let leaf = try authority.leafCertificate(for: "example.com")
        XCTAssertEqual(try XCTUnwrap(leaf.extensions.authorityKeyIdentifier?.keyIdentifier), caIdentifier)
        XCTAssertNotNil(try leaf.extensions.subjectKeyIdentifier)
        // A CA reloaded from disk must keep issuing matching leaves.
        let reloaded = try CertificateAuthority(directory: directory)
        XCTAssertEqual(try reloaded.leafCertificate(for: "example.com").extensions.authorityKeyIdentifier?.keyIdentifier, caIdentifier)
    }
}
