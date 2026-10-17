import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The generated command really runs: real curl, through Watcher, against the echo origin.
@Suite(.tags(.integration, .network, .externalTool), .serialized)
struct CurlEndToEndTests {
    @Test(.enabled(if: ExternalTool.curl.isAvailable, "needs curl"), .tags(.timing))
    func generatedCommandsRunThroughTheProxy() async throws {
        try await withHarness { harness in try runGeneratedCommands(through: harness) }
    }

    private func runGeneratedCommands(through harness: Harness) throws {
        let proxy = "http://127.0.0.1:\(harness.proxyPort)"
        func run(_ request: RequestRecord) throws -> String {
            // upstream.test only resolves inside Watcher (DNS spoofing), so the request must go through the proxy to succeed.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            let command = CodeGenerator.generate(request, as: .curl, proxy: proxy)
            process.arguments = ["-c", command + " --silent --max-time 10"]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(bytes: output, encoding: .utf8) ?? ""
        }
        let port = harness.upstream.port
        func request(_ method: String, _ body: Data = Data()) -> RequestRecord {
            .fixture(method: method, scheme: "http", host: "upstream.test", port: port, path: "/echo", body: body)
        }
        #expect(try run(request("GET")).hasPrefix("GET /echo"))
        let started = Date()
        #expect(try run(request("HEAD")).hasPrefix("HTTP/1.1 200"), "--head prints the response headers")
        #expect(Date().timeIntervalSince(started) < 5, "HEAD returns at once instead of waiting for a body")
        let binary = Data((0 ... 255).map(UInt8.init))
        #expect(try run(request("POST", binary)).hasSuffix("bytes=256"), "every byte arrives")
        #expect(try run(request("PUT", Data("it's".utf8))).hasPrefix("PUT /echo"))
    }
}
