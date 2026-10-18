import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CurlImportTests {
    @Test
    func parsesChromeCopyAsCurlWithContinuationsAndANSIQuotes() throws {
        let command = """
        curl 'https://api.example.com/v1/users?page=2' \\
          -H 'accept: application/json' \\
          -H 'authorization: Bearer abc.def' \\
          -H $'x-note: it\\'s fine' \\
          --data-raw $'{"name":"Ada\\\\n"}' \\
          --compressed
        """
        let request = try CurlImport.parse(command)
        #expect(request.method == "POST")
        #expect(request.url == "https://api.example.com/v1/users?page=2")
        #expect(request.headers.value(for: "authorization") == "Bearer abc.def")
        #expect(request.headers.value(for: "x-note") == "it's fine")
        #expect(String(bytes: request.body, encoding: .utf8) == #"{"name":"Ada\n"}"#)
        #expect(request.headers.value(for: "accept-encoding") == "gzip, deflate, br")
    }

    @Test(arguments: [
        ("curl example.com", "GET"),
        ("curl -d a=1 example.com", "POST"),
        ("curl -I https://example.com", "HEAD"),
        ("curl -X delete https://example.com/1", "DELETE"),
        ("curl --request=PATCH -d x https://example.com", "PATCH"),
    ])
    func methodIsInferredLikeCurl(command: String, method: String) throws {
        #expect(try CurlImport.parse(command).method == method)
    }

    @Test
    func urlWithoutSchemeGetsHTTPAndKeepsPortAndInlineOptions() throws {
        let request = try CurlImport.parse("curl -sSL --url=localhost:8080/health --max-time 5 -o out.txt -k")
        #expect(request.scheme == "http")
        #expect(request.port == 8080)
        #expect(request.path == "/health")
    }

    @Test
    func authCookiesAgentAndFormBecomeHeadersAndBody() throws {
        let request = try CurlImport.parse(
            #"curl -u 'ada:s3cr=t' -b "sid=1; theme=dark" -A Agent/1 -e https://ref.example "#
                + "-d a=1 -d b=2 https://example.com/login"
        )
        #expect(request.headers.value(for: "authorization") == "Basic " + Data("ada:s3cr=t".utf8).base64EncodedString())
        #expect(request.headers.value(for: "cookie") == "sid=1; theme=dark")
        #expect(request.headers.value(for: "user-agent") == "Agent/1")
        #expect(request.headers.value(for: "referer") == "https://ref.example")
        #expect(String(bytes: request.body, encoding: .utf8) == "a=1&b=2", "several -d are joined with &")
        #expect(request.headers.value(for: "content-type") == "application/x-www-form-urlencoded")
    }

    @Test
    func getMovesDataIntoTheQueryAndURLEncodes() throws {
        let request = try CurlImport.parse(
            "curl -G https://example.com/search?lang=tr --data-urlencode 'q=a b&c' -d n=5"
        )
        #expect(request.method == "GET")
        #expect(request.body.isEmpty)
        #expect(request.path == "/search?lang=tr&q=a%20b%26c&n=5")
    }

    @Test
    func jsonShortcutSetsHeaders() throws {
        let request = try CurlImport.parse(#"curl --json '{"a":1}' https://example.com"#)
        #expect(request.method == "POST")
        #expect(request.headers.value(for: "content-type") == "application/json")
        #expect(request.headers.value(for: "accept") == "application/json")
    }

    @Test
    func doubleQuotesAndEscapesAreUnquotedLikeAShell() throws {
        let request = try CurlImport.parse(#"curl -H "X-Path: \"C:\\dir\" \$HOME" https://example.com/a\ b"#)
        #expect(request.headers.value(for: "x-path") == #""C:\dir" $HOME"#)
        #expect(request.host == "example.com")
    }

    @Test(arguments: [
        ("wget https://example.com", "This is not a curl command."),
        ("curl -s", "The command has no URL."),
        ("curl 'https://example.com", "A single quote is not closed."),
        (#"curl "https://example.com"#, "A double quote is not closed."),
        ("curl -H", "-H needs a value."),
    ])
    func failuresSayWhatIsWrong(command: String, message: String) {
        let error = #expect(throws: (any Error).self) { try CurlImport.parse(command) }
        #expect(error.map { "\($0)" } == message)
    }

    @Test(arguments: [
        ("curl -d @body.json https://example.com", "@body.json"),
        ("curl ftp://example.com/file", "not an http"),
    ])
    func failuresNameWhatIsUnsupported(command: String, fragment: String) {
        let error = #expect(throws: (any Error).self) { try CurlImport.parse(command) }
        #expect(error.map { "\($0)".contains(fragment) } == true)
    }

    @Test
    func dataRawNeverReadsFiles() {
        #expect(throws: Never.self, "--data-raw never reads files") {
            try CurlImport.parse("curl --data-raw @literal https://example.com")
        }
    }

    @Test
    func recognisesPastedCommands() {
        #expect(CurlImport.looksLikeCurl("  curl https://x"))
        #expect(CurlImport.looksLikeCurl("curl\\\n  https://x"))
        #expect(!CurlImport.looksLikeCurl("https://curl.se"))
        #expect(!CurlImport.looksLikeCurl("curly"))
    }

    @Test
    func exportThenImportGivesTheSameRequest() throws {
        let original = RequestRecord.fixture(
            method: "PUT",
            port: 8443,
            path: "/v1/items/7?x=1&y=it's",
            headers: [Header("Content-Type", "application/json"), Header("X-Quote", #"a'b"c"#)],
            body: Data(#"{"note":"it's \"quoted\"\nnext"}"#.utf8)
        )
        let parsed = try CurlImport.parse(CodeGenerator.generate(original, as: .curl))
        #expect(parsed.method == original.method)
        #expect(parsed.url == original.url)
        #expect(parsed.headers == original.headers)
        #expect(parsed.body == original.body)
    }

    @Test(arguments: [
        "curl \\\r\n  -H 'A: b' \\\r\n  https://x.com/",
        "curl https://x.com/\r\n-H 'A: b'",
        "curl -H \"A: \\\r\nb\" https://x.com/",
    ])
    func windowsLineEndingsSeparateWordsAndContinueLines(command: String) throws {
        let request = try CurlImport.parse(command)
        #expect(request.url == "https://x.com/")
        #expect(request.headers.value(for: "a") == "b")
    }

    @Test(arguments: [
        ("curl -G -d 'q=hello world' https://x.com/s", "/s?q=hello%20world"),
        ("curl -G -d 'q=100%' https://x.com/s?a=1", "/s?a=1&q=100%25"),
        ("curl -G -d 'q=%41' https://x.com/s", "/s?q=%41"),
    ])
    func getDataThatIsNotAValidQueryIsEncoded(command: String, path: String) throws {
        #expect(try CurlImport.parse(command).path == path)
    }
}
