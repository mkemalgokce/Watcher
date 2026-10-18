import Foundation
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.e2e, .network, .externalTool))
struct StartCommandTests {
    @Test(.enabled(if: ExternalTool.curl.isAvailable, "needs curl"))
    func proxiesACurlRequestAndWritesItToTheHARFileOnCtrlC() async throws {
        let origin = TestUpstream()
        try await origin.start()
        do {
            try await proxyACurlRequest(to: origin)
        } catch {
            await origin.stop()
            throw error
        }
        await origin.stop()
    }

    private func proxyACurlRequest(to origin: TestUpstream) async throws {
        let home = try TemporaryDirectory(prefix: "watcher-e2e")
        let har = home.appending("session.har")
        let cli = try WatcherCLIProcess(
            binary: WatcherCLIBinary.locate(),
            arguments: ["start", "--port", "0", "--har", har.path],
            home: home.url
        )
        try cli.run()
        let port = try await cli.listeningPort()
        let url = "http://127.0.0.1:\(origin.port)/e2e?run=1"

        let body = try CurlRequest.get(url, throughProxyPort: port)
        let printedTheFlow = await eventually(timeout: 10) { cli.printed.contains("200  GET  \(url)") }
        try await cli.interrupt()

        #expect(body.hasPrefix("GET /e2e?run=1 "))
        #expect(printedTheFlow, "the CLI prints each finished request: \(cli.printed)")
        #expect(cli.terminationStatus == 0)
        let flows = try HAR.flows(from: Data(contentsOf: har))
        let flow = try #require(flows.first)
        #expect(flows.count == 1)
        #expect(flow.request.method == "GET")
        #expect(flow.request.url == url)
        #expect(flow.response?.status == 200)
        // swiftlint:disable:next optional_data_string_conversion
        #expect(flow.response.map { String(decoding: $0.body, as: UTF8.self) } == body)
    }
}
