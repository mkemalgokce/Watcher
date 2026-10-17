import Foundation
@testable import WatcherCore
import XCTest

final class CurlExportTests: XCTestCase {
    private func request(_ method: String, _ url: String = "https://api.example.com/v1/x", headers: [Header] = [], body: Data = Data()) -> RequestRecord {
        let components = URLComponents(string: url)!
        return RequestRecord(
            method: method,
            scheme: components.scheme!,
            host: components.host!,
            port: components.port ?? (components.scheme == "https" ? 443 : 80),
            path: components.percentEncodedPath + (components.percentEncodedQuery.map { "?\($0)" } ?? ""),
            headers: headers,
            body: body
        )
    }

    private func curl(_ request: RequestRecord, proxy: String? = nil, certificate: String? = nil) -> String {
        CodeGenerator.generate(request, as: .curl, proxy: proxy, certificate: certificate)
    }

    func testMethodFlagsAreOnlyAddedWhenCurlWouldGuessWrong() {
        XCTAssertEqual(curl(request("GET")), "curl 'https://api.example.com/v1/x'")
        XCTAssertEqual(curl(request("HEAD")), "curl --head 'https://api.example.com/v1/x'", "-X HEAD makes curl wait for a body")
        XCTAssertFalse(curl(request("POST", body: Data("a=1".utf8))).contains("-X"), "--data already means POST")
        XCTAssertTrue(curl(request("POST")).contains("-X POST"), "a POST without a body needs saying")
        XCTAssertTrue(curl(request("PUT", body: Data("{}".utf8))).hasPrefix("curl -X PUT "))
        XCTAssertTrue(curl(request("DELETE")).contains("-X DELETE"))
        XCTAssertTrue(curl(request("GET", body: Data("q".utf8))).contains("-X GET"), "a GET with a body must not turn into a POST")
    }

    func testAcceptEncodingBecomesCompressedSoTheOutputIsReadable() {
        let command = curl(request("GET", headers: [Header("Accept-Encoding", "gzip, br"), Header("Accept", "*/*")]))
        XCTAssertTrue(command.hasSuffix("-H 'Accept: */*' --compressed"), command)
        XCTAssertFalse(command.contains("Accept-Encoding"))
    }

    func testManagedHeadersAreLeftToCurl() {
        let command = curl(request("GET", headers: [Header("Host", "x"), Header("Content-Length", "3"), Header("Connection", "keep-alive"), Header("X-Id", "1")]))
        XCTAssertEqual(command, "curl 'https://api.example.com/v1/x' -H 'X-Id: 1'")
    }

    func testProxyAddsTheCertificateOnlyForHTTPS() {
        let https = curl(request("GET"), proxy: "http://127.0.0.1:9090", certificate: "/Users/a b/.watcher/watcher-ca.pem")
        XCTAssertTrue(https.contains("-x 'http://127.0.0.1:9090' --cacert '/Users/a b/.watcher/watcher-ca.pem'"), https)
        let http = curl(request("GET", "http://example.com/"), proxy: "http://127.0.0.1:9090", certificate: "/ca.pem")
        XCTAssertFalse(http.contains("--cacert"))
        XCTAssertFalse(curl(request("GET"), certificate: "/ca.pem").contains("--cacert"), "without the proxy curl talks to the real server")
    }

    func testTextBodiesAreQuotedForTheShell() {
        let command = curl(request("POST", body: Data(#"{"name":"it's $HOME `x`"}"#.utf8)))
        XCTAssertTrue(command.hasSuffix(#"--data-raw '{"name":"it'\''s $HOME `x`"}'"#), command)
        XCTAssertEqual(try shell("printf '%s' " + CodeGenerator.shellQuote(#"it's $HOME `x` \n"#)), Data(#"it's $HOME `x` \n"#.utf8))
    }

    func testBinaryBodiesArePipedThroughPrintfByteForByte() throws {
        var bytes = Data((0 ... 255).map(UInt8.init))
        bytes.append(contentsOf: Array("'\\%b".utf8))
        let command = curl(request("POST", body: bytes))
        XCTAssertTrue(command.hasPrefix("printf '%b' '"), command)
        XCTAssertTrue(command.hasSuffix("--data-binary @-"), command)
        let printf = try String(command[..<XCTUnwrap(command.range(of: " | curl")?.lowerBound)])
        XCTAssertEqual(try shell(printf), bytes, "the shell must reproduce every byte, NUL and quotes included")
    }

    func testEveryLanguageKeepsABinaryBody() {
        let binary = request("POST", body: Data([0xFF, 0x00, 0x10]))
        let base64 = Data([0xFF, 0x00, 0x10]).base64EncodedString()
        for language in CodeGenerator.Language.allCases where language != .curl {
            XCTAssertTrue(CodeGenerator.generate(binary, as: language).contains(base64), "\(language) dropped the body")
        }
        XCTAssertTrue(CodeGenerator.generate(binary, as: .python).hasPrefix("import requests\nimport base64"))
        XCTAssertTrue(CodeGenerator.generate(binary, as: .ruby).contains("require 'base64'"))
    }

    func testGoImportsOnlyWhatItUses() {
        let none = CodeGenerator.generate(request("GET"), as: .go)
        XCTAssertFalse(none.contains("\"strings\""), "Go refuses unused imports")
        XCTAssertTrue(none.contains(", nil)"))
        let text = CodeGenerator.generate(request("POST", body: Data("a".utf8)), as: .go)
        XCTAssertTrue(text.contains("\"strings\"") && !text.contains("\"bytes\""))
        let binary = CodeGenerator.generate(request("POST", body: Data([0xFF])), as: .go)
        XCTAssertTrue(binary.contains("\"bytes\"") && binary.contains("\"encoding/base64\"") && !binary.contains("\"strings\""))
    }

    /// Runs `script` in /bin/sh and returns what it printed.
    private func shell(_ script: String) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return output
    }
}

final class CurlImportTests: XCTestCase {
    func testChromeCopyAsCurlWithContinuationsAndANSIQuotes() throws {
        let command = """
        curl 'https://api.example.com/v1/users?page=2' \\
          -H 'accept: application/json' \\
          -H 'authorization: Bearer abc.def' \\
          -H $'x-note: it\\'s fine' \\
          --data-raw $'{"name":"Ada\\\\n"}' \\
          --compressed
        """
        let request = try CurlImport.parse(command)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.url, "https://api.example.com/v1/users?page=2")
        XCTAssertEqual(request.headers.value(for: "authorization"), "Bearer abc.def")
        XCTAssertEqual(request.headers.value(for: "x-note"), "it's fine")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), #"{"name":"Ada\n"}"#)
        XCTAssertEqual(request.headers.value(for: "accept-encoding"), "gzip, deflate, br")
    }

    func testMethodIsInferredLikeCurl() throws {
        XCTAssertEqual(try CurlImport.parse("curl example.com").method, "GET")
        XCTAssertEqual(try CurlImport.parse("curl -d a=1 example.com").method, "POST")
        XCTAssertEqual(try CurlImport.parse("curl -I https://example.com").method, "HEAD")
        XCTAssertEqual(try CurlImport.parse("curl -X delete https://example.com/1").method, "DELETE")
        XCTAssertEqual(try CurlImport.parse("curl --request=PATCH -d x https://example.com").method, "PATCH")
    }

    func testURLWithoutSchemeAndPortAndInlineOptions() throws {
        let request = try CurlImport.parse("curl -sSL --url=localhost:8080/health --max-time 5 -o out.txt -k")
        XCTAssertEqual(request.scheme, "http")
        XCTAssertEqual(request.port, 8080)
        XCTAssertEqual(request.path, "/health")
    }

    func testAuthCookiesAgentAndForm() throws {
        let request = try CurlImport.parse(#"curl -u 'ada:s3cr=t' -b "sid=1; theme=dark" -A Agent/1 -e https://ref.example -d a=1 -d b=2 https://example.com/login"#)
        XCTAssertEqual(request.headers.value(for: "authorization"), "Basic " + Data("ada:s3cr=t".utf8).base64EncodedString())
        XCTAssertEqual(request.headers.value(for: "cookie"), "sid=1; theme=dark")
        XCTAssertEqual(request.headers.value(for: "user-agent"), "Agent/1")
        XCTAssertEqual(request.headers.value(for: "referer"), "https://ref.example")
        XCTAssertEqual(String(decoding: request.body, as: UTF8.self), "a=1&b=2", "several -d are joined with &")
        XCTAssertEqual(request.headers.value(for: "content-type"), "application/x-www-form-urlencoded")
    }

    func testGetMovesDataIntoTheQueryAndURLEncodes() throws {
        let request = try CurlImport.parse("curl -G https://example.com/search?lang=tr --data-urlencode 'q=a b&c' -d n=5")
        XCTAssertEqual(request.method, "GET")
        XCTAssertTrue(request.body.isEmpty)
        XCTAssertEqual(request.path, "/search?lang=tr&q=a%20b%26c&n=5")
    }

    func testJSONShortcutSetsHeaders() throws {
        let request = try CurlImport.parse(#"curl --json '{"a":1}' https://example.com"#)
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers.value(for: "content-type"), "application/json")
        XCTAssertEqual(request.headers.value(for: "accept"), "application/json")
    }

    func testDoubleQuotesAndEscapes() throws {
        let request = try CurlImport.parse(#"curl -H "X-Path: \"C:\\dir\" \$HOME" https://example.com/a\ b"#)
        XCTAssertEqual(request.headers.value(for: "x-path"), #""C:\dir" $HOME"#)
        XCTAssertEqual(request.host, "example.com")
    }

    func testFailuresSayWhatIsWrong() {
        XCTAssertThrowsError(try CurlImport.parse("wget https://example.com")) { XCTAssertEqual("\($0)", "This is not a curl command.") }
        XCTAssertThrowsError(try CurlImport.parse("curl -s")) { XCTAssertEqual("\($0)", "The command has no URL.") }
        XCTAssertThrowsError(try CurlImport.parse("curl 'https://example.com")) { XCTAssertEqual("\($0)", "A single quote is not closed.") }
        XCTAssertThrowsError(try CurlImport.parse(#"curl "https://example.com"#)) { XCTAssertEqual("\($0)", "A double quote is not closed.") }
        XCTAssertThrowsError(try CurlImport.parse("curl -d @body.json https://example.com")) { XCTAssertTrue("\($0)".contains("@body.json")) }
        XCTAssertThrowsError(try CurlImport.parse("curl ftp://example.com/file")) { XCTAssertTrue("\($0)".contains("not an http")) }
        XCTAssertThrowsError(try CurlImport.parse("curl -H")) { XCTAssertEqual("\($0)", "-H needs a value.") }
        XCTAssertNoThrow(try CurlImport.parse("curl --data-raw @literal https://example.com"), "--data-raw never reads files")
    }

    func testRecognisesPastedCommands() {
        XCTAssertTrue(CurlImport.looksLikeCurl("  curl https://x"))
        XCTAssertTrue(CurlImport.looksLikeCurl("curl\\\n  https://x"))
        XCTAssertFalse(CurlImport.looksLikeCurl("https://curl.se"))
        XCTAssertFalse(CurlImport.looksLikeCurl("curly"))
    }

    func testExportThenImportGivesTheSameRequest() throws {
        let original = RequestRecord(
            method: "PUT",
            scheme: "https",
            host: "api.example.com",
            port: 8443,
            path: "/v1/items/7?x=1&y=it's",
            headers: [Header("Content-Type", "application/json"), Header("X-Quote", #"a'b"c"#)],
            body: Data(#"{"note":"it's \"quoted\"\nnext"}"#.utf8)
        )
        let parsed = try CurlImport.parse(CodeGenerator.generate(original, as: .curl))
        XCTAssertEqual(parsed.method, original.method)
        XCTAssertEqual(parsed.url, original.url)
        XCTAssertEqual(parsed.headers, original.headers)
        XCTAssertEqual(parsed.body, original.body)
    }
}

/// The generated command really runs: real curl, through Watcher, against the echo origin.
final class CurlEndToEndTests: XCTestCase {
    func testGeneratedCommandsRunThroughTheProxy() async throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/curl") else { throw XCTSkip("curl is not installed") }
        let harness = try Harness()
        try await harness.start()
        defer { Task { await harness.stop() } }
        let proxy = "http://127.0.0.1:\(harness.proxyPort)"
        func run(_ request: RequestRecord) throws -> String {
            // upstream.test only resolves inside Watcher (DNS spoofing), so the request must go through the proxy to succeed.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", CodeGenerator.generate(request, as: .curl, proxy: proxy) + " --silent --max-time 10"]
            let pipe = Pipe(); process.standardOutput = pipe
            try process.run()
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: output, as: UTF8.self)
        }
        let port = harness.upstream.port
        func request(_ method: String, _ body: Data = Data()) -> RequestRecord {
            RequestRecord(method: method, scheme: "http", host: "upstream.test", port: port, path: "/echo", body: body)
        }
        XCTAssertTrue(try run(request("GET")).hasPrefix("GET /echo"))
        let started = Date()
        XCTAssertTrue(try run(request("HEAD")).hasPrefix("HTTP/1.1 200"), "--head prints the response headers")
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "HEAD returns at once instead of waiting for a body")
        let binary = Data((0 ... 255).map(UInt8.init))
        XCTAssertTrue(try run(request("POST", binary)).hasSuffix("bytes=256"), "every byte arrives")
        XCTAssertTrue(try run(request("PUT", Data("it's".utf8))).hasPrefix("PUT /echo"))
    }
}
