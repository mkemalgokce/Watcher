import Foundation
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.e2e, .network, .externalTool))
struct StartCommandTests {
    @Test(.enabled(if: ExternalTool.curl.isAvailable, "needs curl"))
    func proxiesACurlRequestAndWritesItToTheHARAndCSVFilesOnCtrlC() async throws {
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

    @Test(arguments: [SIGINT, SIGTERM, SIGHUP])
    func everyStopSignalSavesTheSessionAndExitsCleanly(signal: Int32) async throws {
        try await withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let csv = home.appending("session.csv")
            let cli = try WatcherCLIProcess(
                binary: WatcherCLIBinary.locate(),
                arguments: ["start", "--port", "0", "--csv", csv.path],
                home: home.url
            )
            try cli.run()
            _ = try await cli.listeningPort()

            try await cli.stop(with: signal)

            #expect(cli.terminationStatus == 0)
            #expect(cli.printed.hasSuffix("Saved \(csv.path)\n"))
            #expect(FileManager.default.fileExists(atPath: csv.path))
        }
    }

    private func proxyACurlRequest(to origin: TestUpstream) async throws {
        try await withTemporaryDirectory(prefix: "watcher-e2e") { home in
            let har = home.appending("session.har")
            let csv = home.appending("session.csv")
            let cli = try WatcherCLIProcess(
                binary: WatcherCLIBinary.locate(),
                arguments: ["start", "--port", "0", "--har", har.path, "--csv", csv.path],
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
            #expect(cli.printed.hasSuffix("Saved \(har.path)\nSaved \(csv.path)\n"))
            #expect(try String(contentsOf: csv, encoding: .utf8).contains(url))
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
}
