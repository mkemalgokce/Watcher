import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CurlExportTests {
    private func request(
        _ method: String,
        _ url: String = "https://api.example.com/v1/x",
        headers: [Header] = [],
        body: Data = Data()
    ) -> RequestRecord {
        .fixture(method: method, url: url, headers: headers, body: body)
    }

    private func curl(_ request: RequestRecord, proxy: String? = nil, certificate: String? = nil) -> String {
        CodeGenerator.generate(request, as: .curl, proxy: proxy, certificate: certificate)
    }

    @Test
    func methodFlagsAreOnlyAddedWhenCurlWouldGuessWrong() {
        #expect(curl(request("GET")) == "curl 'https://api.example.com/v1/x'")
        #expect(
            curl(request("HEAD")) == "curl --head 'https://api.example.com/v1/x'",
            "-X HEAD makes curl wait for a body"
        )
        #expect(!curl(request("POST", body: Data("a=1".utf8))).contains("-X"), "--data already means POST")
        #expect(curl(request("POST")).contains("-X POST"), "a POST without a body needs saying")
        #expect(curl(request("PUT", body: Data("{}".utf8))).hasPrefix("curl -X PUT "))
        #expect(curl(request("DELETE")).contains("-X DELETE"))
        #expect(
            curl(request("GET", body: Data("q".utf8))).contains("-X GET"),
            "a GET with a body must not turn into a POST"
        )
    }

    @Test
    func acceptEncodingBecomesCompressedSoTheOutputIsReadable() {
        let command = curl(request("GET", headers: [Header("Accept-Encoding", "gzip, br"), Header("Accept", "*/*")]))
        #expect(command.hasSuffix("-H 'Accept: */*' --compressed"), "\(command)")
        #expect(!command.contains("Accept-Encoding"))
    }

    @Test
    func managedHeadersAreLeftToCurl() {
        let command = curl(request("GET", headers: [
            Header("Host", "x"),
            Header("Content-Length", "3"),
            Header("Connection", "keep-alive"),
            Header("X-Id", "1"),
        ]))
        #expect(command == "curl 'https://api.example.com/v1/x' -H 'X-Id: 1'")
    }

    @Test
    func proxyAddsTheCertificateOnlyForHTTPS() {
        let https = curl(
            request("GET"),
            proxy: "http://127.0.0.1:9090",
            certificate: "/Users/a b/.watcher/watcher-ca.pem"
        )
        #expect(https.contains("-x 'http://127.0.0.1:9090' --cacert '/Users/a b/.watcher/watcher-ca.pem'"), "\(https)")
        let http = curl(request("GET", "http://example.com/"), proxy: "http://127.0.0.1:9090", certificate: "/ca.pem")
        #expect(!http.contains("--cacert"))
        #expect(
            !curl(request("GET"), certificate: "/ca.pem").contains("--cacert"),
            "without the proxy curl talks to the real server"
        )
    }

    @Test
    func textBodiesAreQuotedForTheShell() throws {
        let command = curl(request("POST", body: Data(#"{"name":"it's $HOME `x`"}"#.utf8)))
        #expect(command.hasSuffix(#"--data-raw '{"name":"it'\''s $HOME `x`"}'"#), "\(command)")
        let quoted = CodeGenerator.shellQuote(#"it's $HOME `x` \n"#)
        #expect(try shell("printf '%s' " + quoted) == Data(#"it's $HOME `x` \n"#.utf8))
    }

    @Test
    func singleQuotesInABodyAreEscapedAndManagedHeadersDropped() {
        let request = Flow.jsonPostFixture().request
        let curl = CodeGenerator.generate(request, as: .curl)
        #expect(curl.contains(#"--data-raw '{"name":"it'\''s"}'"#), "\(curl)")
        #expect(CodeGenerator.generate(request, as: .swift).contains("httpMethod = \"POST\""))
    }

    @Test
    func binaryBodiesArePipedThroughPrintfByteForByte() throws {
        var bytes = Data((0 ... 255).map(UInt8.init))
        bytes.append(contentsOf: Array("'\\%b".utf8))
        let command = curl(request("POST", body: bytes))
        #expect(command.hasPrefix("printf '%b' '"), "\(command)")
        #expect(command.hasSuffix("--data-binary @-"), "\(command)")
        let printf = try String(command[..<#require(command.range(of: " | curl")?.lowerBound)])
        #expect(try shell(printf) == bytes, "the shell must reproduce every byte, NUL and quotes included")
    }

    @Test(arguments: CodeGenerator.Language.allCases.filter { $0 != .curl })
    func everyLanguageKeepsABinaryBody(_ language: CodeGenerator.Language) {
        let binary = request("POST", body: Data([0xFF, 0x00, 0x10]))
        let base64 = Data([0xFF, 0x00, 0x10]).base64EncodedString()
        #expect(CodeGenerator.generate(binary, as: language).contains(base64), "\(language) dropped the body")
    }

    @Test
    func pythonAndRubyImportBase64ForABinaryBody() {
        let binary = request("POST", body: Data([0xFF, 0x00, 0x10]))
        #expect(CodeGenerator.generate(binary, as: .python).hasPrefix("import requests\nimport base64"))
        #expect(CodeGenerator.generate(binary, as: .ruby).contains("require 'base64'"))
    }

    @Test
    func goImportsOnlyWhatItUses() {
        let none = CodeGenerator.generate(request("GET"), as: .go)
        #expect(!none.contains("\"strings\""), "Go refuses unused imports")
        #expect(none.contains(", nil)"))
        let text = CodeGenerator.generate(request("POST", body: Data("a".utf8)), as: .go)
        #expect(text.contains("\"strings\"") && !text.contains("\"bytes\""))
        let binary = CodeGenerator.generate(request("POST", body: Data([0xFF])), as: .go)
        #expect(binary.contains("\"bytes\"") && binary.contains("\"encoding/base64\""))
        #expect(!binary.contains("\"strings\""))
    }

    private func shell(_ script: String) throws -> Data {
        try ExternalTool.shell.run(["-c", script]).data
    }
}
