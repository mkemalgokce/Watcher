import Foundation
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// The logic behind the inspector tabs and the Compose window, without drawing anything.
@MainActor
final class ViewModelTests: XCTestCase {
    private func flow(_ n: Int, path: String = "/v1/users", body: String = "", duration: TimeInterval? = 1, firstByte: TimeInterval? = nil, state: Flow.State = .completed) -> Flow {
        var flow = Flow(sequence: n, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: path))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json")], body: Data(body.utf8))
        flow.state = state; flow.duration = duration; flow.timeToFirstByte = firstByte
        return flow
    }

    // MARK: Timing

    func testTimingSplitsWaitingAndDownload() {
        let timing = TimingBreakdown(flow(1, duration: 2, firstByte: 0.5))
        XCTAssertTrue(timing.isComplete)
        XCTAssertEqual(timing.phases.map(\.seconds), [0.5, 1.5])
        XCTAssertEqual(timing.phases.map(\.fraction), [0.25, 0.75])
        XCTAssertTrue(timing.verdict.contains("downloading"))
    }

    func testTimingEdgeCases() {
        // No first-byte time: everything counts as waiting.
        XCTAssertEqual(TimingBreakdown(flow(1, duration: 1)).phases.map(\.fraction), [1, 0])
        XCTAssertTrue(TimingBreakdown(flow(1, duration: 1)).verdict.contains("server"))
        // A first byte after the end (clock skew) never yields a negative phase.
        XCTAssertEqual(TimingBreakdown(flow(1, duration: 1, firstByte: 3)).phases.map(\.seconds), [1, 0])
        // Not finished, or zero length.
        let pending = TimingBreakdown(flow(1, duration: nil, state: .pending))
        XCTAssertFalse(pending.isComplete)
        XCTAssertEqual(pending.phases.map(\.fraction), [0, 0])
        XCTAssertEqual(pending.verdict, "The response has not finished yet.")
        XCTAssertTrue(TimingBreakdown(flow(1, duration: 0.05)).verdict.hasPrefix("Fast"))
    }

    // MARK: Diff

    func testDiffStates() async {
        let viewModel = DiffViewModel()
        let a = flow(1, body: #"{"a":1}"#), b = flow(2, body: #"{"a":2}"#), c = flow(3, body: #"{"a":1}"#)
        await viewModel.update(base: nil, current: a)
        XCTAssertEqual(viewModel.state, .noBase)
        await viewModel.update(base: a, current: a)
        XCTAssertEqual(viewModel.state, .sameFlow)
        await viewModel.update(base: a, current: b)
        guard case let .ready(changed) = viewModel.state else { return XCTFail("\(viewModel.state)") }
        XCTAssertEqual(changed.added, 1); XCTAssertEqual(changed.removed, 1)
        await viewModel.update(base: a, current: c)
        guard case let .ready(same) = viewModel.state else { return XCTFail("\(viewModel.state)") }
        XCTAssertTrue(same.isIdentical)
    }

    func testDiffSubjects() {
        var a = flow(1), b = flow(2)
        a.request.headers = [Header("X-Trace", "1")]; b.request.headers = [Header("X-Trace", "2")]
        XCTAssertTrue(DiffViewModel.text(a, .headers).contains("X-Trace: 1"))
        XCTAssertFalse(DiffViewModel.compare(DiffViewModel.text(a, .headers), DiffViewModel.text(b, .headers)).isIdentical)
        XCTAssertTrue(DiffViewModel.compare(DiffViewModel.text(a, .requestBody), DiffViewModel.text(b, .requestBody)).isIdentical)
        var noResponse = flow(3); noResponse.response = nil
        XCTAssertEqual(DiffViewModel.text(noResponse, .responseBody), "")
    }

    func testSuggestedBaseIsTheEarlierCallToTheSameEndpoint() {
        let flows = [flow(1, path: "/v1/users?page=1"), flow(2, path: "/v1/other"), flow(3, path: "/v1/users?page=2"), flow(4, path: "/v1/users")]
        XCTAssertEqual(DiffViewModel.suggestedBase(for: flows[3], in: flows)?.sequence, 3)
        XCTAssertNil(DiffViewModel.suggestedBase(for: flows[0], in: flows), "nothing earlier")
        XCTAssertNil(DiffViewModel.suggestedBase(for: flows[1], in: flows), "no other call to that path")
    }

    // MARK: Compose

    func testComposeKeepsURLAndParamsInSync() {
        let viewModel = ComposeViewModel()
        viewModel.address = "https://api.example.com/search?q=swift&page=2"
        XCTAssertEqual(viewModel.params.map(\.name), ["q", "page"])
        viewModel.params[1].value = "3"
        XCTAssertEqual(viewModel.address, "https://api.example.com/search?q=swift&page=3")
        viewModel.params[0].isEnabled = false
        XCTAssertEqual(viewModel.address, "https://api.example.com/search?page=3")
        XCTAssertEqual(viewModel.params.count, 2, "a switched-off parameter stays in the list")
        XCTAssertEqual(viewModel.badge(.params), "1")
    }

    func testPastingCurlFillsTheForm() {
        let viewModel = ComposeViewModel()
        viewModel.address = #"curl -X POST 'https://api.example.com/v1/items' -H 'Content-Type: application/json' --data-raw '{"name":"A"}'"#
        XCTAssertEqual(viewModel.method, "POST")
        XCTAssertEqual(viewModel.address, "https://api.example.com/v1/items")
        XCTAssertEqual(viewModel.bodyKind, .json)
        XCTAssertEqual(viewModel.bodyText, #"{"name":"A"}"#)
        XCTAssertEqual(viewModel.tab, .body)
        XCTAssertNil(viewModel.problem)
    }

    func testBrokenCurlIsReported() {
        let viewModel = ComposeViewModel()
        viewModel.address = "curl -H"
        XCTAssertNotNil(viewModel.problem)
    }

    func testBuildAddsAuthAndRejectsBadURLs() throws {
        let viewModel = ComposeViewModel()
        viewModel.address = "ftp://example.com"
        XCTAssertThrowsError(try viewModel.build())
        viewModel.address = "https://api.example.com:8443/x"
        viewModel.auth = .bearer; viewModel.token = "t0k"
        let request = try viewModel.build()
        XCTAssertEqual(request.port, 8443)
        XCTAssertEqual(request.headers.value(for: "Authorization"), "Bearer t0k")
        viewModel.headers.append(KeyValue("Authorization", "Custom"))
        XCTAssertEqual(try viewModel.build().headers.value(for: "Authorization"), "Custom", "a header you add wins")
        viewModel.bodyKind = .binary
        XCTAssertThrowsError(try viewModel.build(), "binary without a file")
    }

    func testSendStates() async {
        let viewModel = ComposeViewModel()
        viewModel.address = "https://api.example.com/x"
        await viewModel.send(isProxyRunning: false) { _, _ in XCTFail("must not send"); return ResponseRecord(status: 200, headers: [], body: Data()) }
        XCTAssertEqual(viewModel.phase, .failed("Start the proxy to send requests."))

        await viewModel.send(isProxyRunning: true) { request, follow in
            XCTAssertFalse(follow)
            XCTAssertEqual(request.host, "api.example.com")
            return ResponseRecord(status: 201, headers: [], body: Data("ok".utf8))
        }
        XCTAssertEqual(viewModel.result?.response?.status, 201)
        XCTAssertNil(viewModel.problem)

        await viewModel.send(isProxyRunning: true) { _, _ in ResponseRecord(status: 502, headers: [], body: Data("down".utf8)) }
        XCTAssertEqual(viewModel.result?.response?.status, 502, "the error answer is still shown")
        XCTAssertEqual(viewModel.problem, "The server answered 502 Bad Gateway. See the response below.")

        viewModel.address = "nonsense"
        await viewModel.send(isProxyRunning: true) { _, _ in XCTFail("must not send"); return ResponseRecord(status: 200, headers: [], body: Data()) }
        if case .failed = viewModel.phase {} else {
            XCTFail("an invalid URL fails before sending")
        }
    }

    func testLoadingACapturedRequestDropsTransportHeaders() {
        let viewModel = ComposeViewModel()
        viewModel.load(RequestRecord(
            method: "PUT",
            scheme: "https",
            host: "h.example",
            port: 443,
            path: "/a?x=1",
            headers: [Header("Host", "h.example"), Header("Content-Length", "2"), Header("X-Keep", "1")],
            body: Data("hi".utf8)
        ))
        XCTAssertEqual(viewModel.method, "PUT")
        XCTAssertEqual(viewModel.headers.map(\.name), ["X-Keep"])
        XCTAssertEqual(viewModel.params.map(\.name), ["x"])
        XCTAssertEqual(viewModel.bodyText, "hi")
    }
}

/// Editing a message paused at a breakpoint.
@MainActor
final class HitEditorViewModelTests: XCTestCase {
    private func requestHit() -> BreakpointCenter.Hit {
        .init(phase: .request, request: RequestRecord(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            path: "/v1/login",
            headers: [Header("Content-Type", "application/json"), Header("Content-Length", "14")],
            body: Data(#"{"user":"ada"}"#.utf8)
        ))
    }

    func testEditedRequestIsRebuiltFromTheForm() {
        let viewModel = HitEditorViewModel(hit: requestHit())
        XCTAssertEqual(viewModel.urlText, "https://api.example.com/v1/login")
        viewModel.method = "PUT"
        viewModel.urlText = "http://staging.example.com:8080/v2/login?x=1"
        viewModel.bodyText = #"{"user":"grace"}"#
        guard case let .proceed(request, response) = viewModel.resolution() else { return XCTFail("expected an edited request") }
        XCTAssertNil(response)
        XCTAssertEqual(request.method, "PUT")
        XCTAssertEqual(request.scheme, "http"); XCTAssertEqual(request.host, "staging.example.com"); XCTAssertEqual(request.port, 8080)
        XCTAssertEqual(request.path, "/v2/login?x=1")
        XCTAssertNil(request.headers.value(for: "Content-Length"), "a stale length would cut the edited body")
        XCTAssertEqual(String(data: request.body, encoding: .utf8), #"{"user":"grace"}"#)
    }

    func testInvalidFormsCannotBeSent() {
        let request = HitEditorViewModel(hit: requestHit())
        for bad in ["", "api.example.com/x", "ftp://example.com/x", "https://"] {
            request.urlText = bad
            XCTAssertFalse(request.canExecute, bad)
            XCTAssertNil(request.resolution(), bad)
        }
        let response = HitEditorViewModel(hit: .init(
            phase: .response,
            request: requestHit().request,
            response: ResponseRecord(status: 200, headers: [], body: Data())
        ))
        for bad in ["", "abc", "99", "600"] {
            response.status = bad; XCTAssertFalse(response.canExecute, bad)
        }
        response.status = " 404 "
        XCTAssertEqual(response.statusCode, 404)
    }

    func testEditedResponseAndTemplates() {
        let viewModel = HitEditorViewModel(hit: .init(
            phase: .response,
            request: requestHit().request,
            response: ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json")], body: Data(#"{"a":1}"#.utf8))
        ))
        XCTAssertTrue(viewModel.isResponse)
        XCTAssertEqual(viewModel.bodyLanguage, .json)
        let template = BreakpointTemplate.builtIn[0]
        viewModel.apply(template)
        XCTAssertEqual(viewModel.status, "\(template.status)")
        guard case let .proceed(_, edited) = viewModel.resolution(), let response = edited else { return XCTFail("expected an edited response") }
        XCTAssertEqual(response.status, template.status)
        XCTAssertEqual(String(data: response.body, encoding: .utf8), template.body)
    }
}

/// Multi-line cURL and reason phrases, which the redesigned inspector shows.
final class CodeAndStatusTests: XCTestCase {
    func testMultilineCurlKeepsOptionsWithTheirValues() {
        let request = RequestRecord(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            path: "/v1",
            headers: [Header("Accept", "*/*"), Header("Accept-Encoding", "gzip")],
            body: Data("x=1".utf8)
        )
        let code = CodeGenerator.generate(request, as: .curl, multiline: true)
        XCTAssertEqual(code, """
        curl 'https://api.example.com/v1' \\
          -H 'Accept: */*' \\
          --compressed \\
          --data-raw 'x=1'
        """)
        XCTAssertEqual(CodeGenerator.generate(request, as: .curl), "curl 'https://api.example.com/v1' -H 'Accept: */*' --compressed --data-raw 'x=1'")
    }

    func testReasonPhrases() {
        XCTAssertEqual(HTTPStatus.reason(200), "OK")
        XCTAssertEqual(HTTPStatus.reason(404), "Not Found")
        XCTAssertEqual(HTTPStatus.reason(502), "Bad Gateway")
        XCTAssertFalse(HTTPStatus.reason(299).isEmpty)
    }
}

/// Device setup: scanning, trust and the status of the last action, with the system calls replaced.
@MainActor
final class DevicesViewModelTests: XCTestCase {
    private struct Boom: Error, CustomStringConvertible { var description: String {
        "adb: device offline"
    } }

    private func viewModel(trusted: Bool = true) -> DevicesViewModel {
        let simulator = SimulatorCertificate.Simulator(udid: "U1", name: "iPhone 17", runtime: "iOS 26", isBooted: true)
        return DevicesViewModel(
            probe: .init(simulators: { [simulator] }, androidDevices: { [] }, isMacTrusted: { trusted }),
            certificateURL: URL(fileURLWithPath: "/tmp/ca.pem")
        )
    }

    func testRefreshFillsTheListsAndEndsTheScan() async {
        let devices = viewModel()
        XCTAssertTrue(devices.simulators.isEmpty)
        await devices.refresh()
        XCTAssertFalse(devices.isScanning)
        XCTAssertEqual(devices.simulators.map(\.name), ["iPhone 17"])
        XCTAssertTrue(devices.androidDevices.isEmpty)
        XCTAssertTrue(devices.macTrusted)
    }

    func testTrustCheckAlone() async {
        let devices = viewModel(trusted: false)
        await devices.refreshMacTrust()
        XCTAssertFalse(devices.macTrusted)
        XCTAssertTrue(devices.simulators.isEmpty, "the cheap check does not run simctl")
    }

    func testActionsReportSuccessAndFailure() async {
        let devices = viewModel()
        await devices.run("Working…", done: "Done.") {}
        XCTAssertEqual(devices.status, .done("Done."))
        await devices.run("Working…", done: "Done.") { throw Boom() }
        XCTAssertEqual(devices.status, .failed("adb: device offline"))
        XCTAssertEqual(devices.simulators.count, 1, "the panes are rescanned after an action")
    }

    func testPreviewProbeFindsNothing() async {
        let devices = DevicesViewModel(probe: .none, certificateURL: URL(fileURLWithPath: "/tmp/ca.pem"))
        await devices.refresh()
        XCTAssertTrue(devices.simulators.isEmpty && devices.androidDevices.isEmpty && !devices.macTrusted)
    }
}

/// Rule list editing in Tools: what is selected after each change.
final class RuleListTests: XCTestCase {
    private func rule(_ name: String) -> BlockRule {
        BlockRule(name: name, matching: MatchingRule(pattern: "\(name)/*"))
    }

    func testAddSwitchesTheToolOnAndSelectsTheNewRule() {
        var set = RuleSet<BlockRule>()
        XCTAssertFalse(set.isEnabled)
        XCTAssertEqual(set.add(rule("a")), 0)
        XCTAssertTrue(set.isEnabled)
        XCTAssertEqual(set.add(rule("b")), 1)
    }

    func testRemoveSelectsTheNeighbour() {
        var set = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a"), rule("b"), rule("c")])
        XCTAssertEqual(set.remove(at: 1), 1, "the next rule moves up into the selection")
        XCTAssertEqual(set.rules.map(\.name), ["a", "c"])
        XCTAssertEqual(set.remove(at: 1), 0, "removing the last selects the new last")
        XCTAssertNil(set.remove(at: 0), "nothing left to select")
        XCTAssertNil(set.remove(at: 5), "out of range on an empty list")
        var other = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a")])
        XCTAssertEqual(other.remove(at: 9), 0, "a stale index changes nothing")
        XCTAssertEqual(other.rules.count, 1)
    }

    func testDuplicateInsertsAfterTheOriginal() {
        var set = RuleSet<BlockRule>(isEnabled: true, rules: [rule("a"), rule("b")])
        XCTAssertEqual(set.duplicate(at: 0), 1)
        XCTAssertEqual(set.rules.map(\.name), ["a", "a", "b"])
        XCTAssertNil(set.duplicate(at: 7))
    }

    func testActiveCountsIgnoreDisabledRulesAndTools() {
        var settings = WatcherSettings()
        settings.blockList = RuleSet(isEnabled: true, rules: [rule("a"), BlockRule(name: "off", isEnabled: false, matching: MatchingRule(pattern: "*"))])
        XCTAssertEqual(ToolsView.Tool.block.activeCount(in: settings), 1)
        settings.blockList.isEnabled = false
        XCTAssertEqual(ToolsView.Tool.block.activeCount(in: settings), 0)
        settings.throttle.isEnabled = true
        XCTAssertEqual(ToolsView.Tool.throttling.activeCount(in: settings), 1)
    }
}

/// Edit & Repeat and the developer helpers around bodies.
@MainActor
final class DeveloperActionTests: XCTestCase {
    private let captured = RequestRecord(
        method: "POST",
        scheme: "https",
        host: "api.example.com",
        port: 443,
        path: "/v1/items?x=1",
        headers: [Header("Content-Type", "application/json"), Header("X-Trace", "1"), Header("Content-Length", "11")],
        body: Data(#"{"name":"A"}"#.utf8)
    )

    func testEditAndRepeatListsChangesAndResets() {
        let viewModel = ComposeViewModel()
        viewModel.load(captured, asOriginal: true)
        XCTAssertEqual(viewModel.changes, [], "loading alone changes nothing; transport headers do not count")

        viewModel.method = "PUT"
        viewModel.headers.removeAll { $0.name == "X-Trace" }
        viewModel.bodyText = #"{"name":"B"}"#
        XCTAssertEqual(viewModel.changes, ["method", "1 header", "body"])
        viewModel.address = "https://api.example.com/v2/items?x=1"
        XCTAssertTrue(viewModel.changes.contains("URL"))

        viewModel.resetToOriginal()
        XCTAssertEqual(viewModel.changes, [])
        XCTAssertEqual(viewModel.method, "POST")
        XCTAssertEqual(viewModel.address, captured.url)
        XCTAssertEqual(viewModel.phase, .idle)
    }

    func testNewRequestHasNoOriginal() {
        let viewModel = ComposeViewModel()
        viewModel.load(captured)
        XCTAssertNil(viewModel.original)
        XCTAssertEqual(viewModel.changes, [])
        viewModel.resetToOriginal() // nothing to go back to: no-op
        XCTAssertEqual(viewModel.method, "POST")
    }

    func testCompareWithOriginalSelectsTheResentRequest() {
        let model = AppModel(listening: false)
        var original = Flow(sequence: 1, request: captured); original.state = .completed
        var other = Flow(sequence: 2, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/other")); other.state = .completed
        var resent = Flow(sequence: 3, request: captured); resent.state = .completed
        [original, other, resent].forEach { model.enqueue(.added($0)) }
        model.flushEvents()
        model.editAndRepeat(original)
        XCTAssertEqual(model.sheet, .compose)
        XCTAssertEqual(model.composeSource?.id, original.id)

        model.compareWithOriginal(original, sent: captured)
        XCTAssertEqual(model.diffBase?.id, original.id)
        XCTAssertEqual(model.selection, resent.id)
        XCTAssertNil(model.sheet)
    }

    func testSuggestedFileNames() {
        let model = AppModel(listening: false)
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "h", port: 443, path: "/v1/users?page=2"))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json; charset=utf-8")], body: Data("{}".utf8))
        XCTAssertEqual(model.suggestedFileName(for: flow, side: .response), "users.json")
        flow.request.path = "/files/report.pdf"
        XCTAssertEqual(model.suggestedFileName(for: flow, side: .response), "report.pdf", "an extension in the URL is kept")
        flow.request.path = "/"
        XCTAssertEqual(model.suggestedFileName(for: flow, side: .response), "response.json")
        flow.response?.headers = []
        XCTAssertEqual(model.suggestedFileName(for: flow, side: .response), "response")
    }

    func testEmbeddedBase64IsFoundAndDescribed() {
        // A 1×1 PNG and a small PDF header inside JSON, as an API would return them.
        let png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        let pdf = Data("%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF".utf8).base64EncodedString()
        let body = Data(#"{"avatar":"\#(png)","invoice":"\#(pdf)","name":"Ada"}"#.utf8)
        let segments = EmbeddedDataIndex.scan(body, contentEncoding: nil)
        XCTAssertEqual(segments.count, 2)
        let image = segments.first {
            if case .image = $0.kind {
                true
            } else {
                false
            }
        }
        XCTAssertEqual(image?.label, "avatar")
        XCTAssertEqual(image?.mimeType, "image/png")
        XCTAssertEqual(image?.suggestedFileName, "avatar.png")
        let document = segments.first { $0.isPDF }
        XCTAssertEqual(document?.kindName, "PDF")
        XCTAssertEqual(document?.suggestedFileName, "invoice.pdf")

        XCTAssertTrue(EmbeddedDataIndex.scan(Data(), contentEncoding: nil).isEmpty)
        XCTAssertTrue(EmbeddedDataIndex.scan(Data(repeating: 0xFF, count: 64), contentEncoding: nil).isEmpty, "binary bodies are not searched")
    }

    func testEmbeddedResultsAreCachedPerBody() {
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "h", port: 443, path: "/"))
        flow.response = ResponseRecord(status: 200, headers: [], body: Data(#"{"a":"aGVsbG8gd29ybGQsIHRoaXMgaXMgYSB0ZXN0IHN0cmluZw=="}"#.utf8))
        let first = EmbeddedDataIndex.shared.segments(in: flow, side: .response)
        let second = EmbeddedDataIndex.shared.segments(in: flow, side: .response)
        XCTAssertEqual(first.map(\.id), second.map(\.id), "the second call is answered from the cache")
        XCTAssertTrue(EmbeddedDataIndex.shared.segments(in: flow, side: .request).isEmpty)
    }
}

/// Rule mistakes Tools warns about, so a rule never fails silently.
final class ToolValidationTests: XCTestCase {
    func testPatterns() {
        XCTAssertEqual(ToolValidation.problems(MatchingRule(pattern: "api.example.com/*")), [])
        XCTAssertEqual(ToolValidation.problems(MatchingRule(pattern: "  ")).count, 1, "empty matches everything")
        var regex = MatchingRule(pattern: "api\\.example\\.com/v[0-9]+")
        regex.mode = .regex
        XCTAssertEqual(ToolValidation.problems(regex), [])
        regex.pattern = "api.example.com/(v1"
        XCTAssertEqual(ToolValidation.problems(regex).count, 1, "an unbalanced group does not compile")
    }

    func testDNSSpoofing() {
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "api.example.com", address: "127.0.0.1")), [])
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "api.example.com", address: "::1")), [], "IPv6 is fine")
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "api.example.com", address: "256.1.1.1")).count, 1)
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "api.example.com", address: "localhost")).count, 1, "a name is not an address")
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "https://api.example.com/", address: "10.0.0.1")).count, 1)
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "*.example.com", address: "10.0.0.1")).count, 1)
        XCTAssertEqual(ToolValidation.problems(DNSSpoofRule(host: "", address: "")).count, 2)
    }

    func testReverseProxies() {
        let rule = ReverseProxyRule(localPort: 9191, remoteHost: "api.example.com")
        XCTAssertEqual(ToolValidation.problems(rule, proxyPort: 9090, others: []), [])
        XCTAssertEqual(ToolValidation.problems(ReverseProxyRule(localPort: 9090, remoteHost: "x"), proxyPort: 9090, others: []).count, 1)
        XCTAssertEqual(ToolValidation.problems(rule, proxyPort: 9090, others: [ReverseProxyRule(localPort: 9191, remoteHost: "other")]).count, 1)
        var disabled = ReverseProxyRule(localPort: 9191, remoteHost: "other"); disabled.isEnabled = false
        XCTAssertEqual(ToolValidation.problems(rule, proxyPort: 9090, others: [disabled]), [], "a switched-off rule does not hold the port")
        XCTAssertEqual(ToolValidation.problems(ReverseProxyRule(localPort: 9191, remoteHost: " "), proxyPort: 9090, others: []).count, 1)
    }

    func testCertificates() {
        let rule = CustomCertificateRule(host: "api.example.com", role: .client, p12Path: "~/certs/client.p12")
        XCTAssertEqual(ToolValidation.problems(rule, fileExists: { $0.hasSuffix("/certs/client.p12") && !$0.hasPrefix("~") }), [], "~ is expanded")
        XCTAssertEqual(ToolValidation.problems(rule, fileExists: { _ in false }), ["No file at ~/certs/client.p12."])
        XCTAssertEqual(ToolValidation.problems(CustomCertificateRule(host: "", role: .server, p12Path: "")).count, 2)
    }
}

/// The Tools sidebar: counts, problem marks and the spoken summary come from the view model.
@MainActor
final class ToolsViewModelTests: XCTestCase {
    func testSummariesAndProblems() {
        let model = AppModel(listening: false)
        let tools = ToolsViewModel(model: model)
        XCTAssertEqual(tools.summary(.block), "Off")

        model.settings.blockList = RuleSet(isEnabled: true, rules: [BlockRule(name: "ads", matching: MatchingRule(pattern: "ads.example.com/*"))])
        XCTAssertEqual(tools.summary(.block), "1 rule on")
        XCTAssertTrue(tools.problems(.block).isEmpty)

        model.settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [DNSSpoofRule(host: "api.example.com", address: "nope")])
        XCTAssertEqual(tools.summary(.dns), "1 rule needs attention")
        model.settings.dnsSpoofing.rules[0].isEnabled = false
        XCTAssertTrue(tools.problems(.dns).isEmpty, "a switched-off rule is not reported")

        model.settings.reverseProxy = RuleSet(isEnabled: true, rules: [ReverseProxyRule(localPort: 9191, remoteHost: "a"), ReverseProxyRule(localPort: 9191, remoteHost: "b")])
        XCTAssertEqual(tools.problems(.reverse).count, 2, "both rules on one port are flagged")

        tools.selection = .dns
        XCTAssertEqual(model.toolsSelection, .dns, "the page choice is the model's, so menus can open Tools on a page")
    }
}
