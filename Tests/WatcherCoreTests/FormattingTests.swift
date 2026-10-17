import Compression
@testable import WatcherCore
import XCTest

final class FormattingTests: XCTestCase {
    func testDetectsLanguageFromContentTypeThenBytes() {
        XCTAssertEqual(BodyLanguage.detect(contentType: "application/json; charset=utf-8", data: Data()), .json)
        XCTAssertEqual(BodyLanguage.detect(contentType: "text/html", data: Data()), .html)
        XCTAssertEqual(BodyLanguage.detect(contentType: "image/png", data: Data([1])), .binary)
        XCTAssertEqual(BodyLanguage.detect(contentType: nil, data: Data("  {\"a\":1}".utf8)), .json)
        XCTAssertEqual(BodyLanguage.detect(contentType: nil, data: Data([0xFF, 0xFE, 0x00])), .binary)
    }

    func testJSONPrettyKeepsOrderStringsAndEmptyContainers() {
        let out = JSONFormatter.pretty(#"{"b":[1,2],"a":{"x":"p,q:{r}"},"e":{},"l":[]}"#)
        XCTAssertEqual(out, """
        {
          "b": [
            1,
            2
          ],
          "a": {
            "x": "p,q:{r}"
          },
          "e": {},
          "l": []
        }
        """)
    }

    func testJSONMinifyRoundTrips() {
        let source = #"{"a": [1, 2], "s": "x y"}"#
        XCTAssertEqual(JSONFormatter.minify(JSONFormatter.pretty(source)), #"{"a":[1,2],"s":"x y"}"#)
        XCTAssertEqual(JSONFormatter.pretty("not json"), "not json")
    }

    func testSortedKeys() throws {
        let sorted = try XCTUnwrap(JSONFormatter.sortedKeys(Data(#"{"b":1,"a":2}"#.utf8)))
        XCTAssertLessThan(try XCTUnwrap(sorted.range(of: "\"a\"")).lowerBound, try XCTUnwrap(sorted.range(of: "\"b\"")).lowerBound)
    }

    func testBeautifyCSSAndJS() {
        XCTAssertEqual(CodeBeautifier.beautify("a{color:red;margin:0}"), "a {\n  color:red;\n  margin:0\n}")
        let js = CodeBeautifier.beautify("for(var i=0;i<3;i++){f(\"a;b\",1)}")
        XCTAssertTrue(js.contains("for(var i=0;i<3;i++) {"), js)
        XCTAssertTrue(js.contains("f(\"a;b\",1)") || js.contains("f(\"a;b\", 1)"), js)
    }

    func testGzipDecode() {
        let raw = Data("hello hello hello hello".utf8)
        var deflated = [UInt8](repeating: 0, count: 256)
        let n = raw.withUnsafeBytes { compression_encode_buffer(&deflated, 256, $0.bindMemory(to: UInt8.self).baseAddress!, raw.count, nil, COMPRESSION_ZLIB) }
        var gz = Data([0x1F, 0x8B, 8, 0, 0, 0, 0, 0, 0, 3]); gz.append(contentsOf: deflated[..<n]); gz.append(Data(count: 8))
        let decoded = BodyDecoder.decode(gz, contentEncoding: "gzip")
        XCTAssertEqual(decoded.data, raw)
        XCTAssertEqual(decoded.removedEncoding, "gzip")
        XCTAssertNil(BodyDecoder.decode(raw, contentEncoding: "identity").removedEncoding)
    }

    func testBodyFormatter() {
        let json = BodyFormatter.format(Data(#"{"a":1}"#.utf8), contentType: "application/json")
        XCTAssertEqual(json.text, "{\n  \"a\": 1\n}"); XCTAssertEqual(json.language, .json)
        XCTAssertEqual(BodyFormatter.format(Data("a=1&b=x+y%21".utf8), contentType: "application/x-www-form-urlencoded").text, "a = 1\nb = x y!")
        let xml = BodyFormatter.format(Data("<a><b>1</b></a>".utf8), contentType: "application/xml")
        XCTAssertTrue(xml.text.contains("\n"), xml.text)
        let bin = BodyFormatter.format(Data([0, 1, 2, 0x41]), contentType: "application/octet-stream")
        XCTAssertEqual(bin.language, .binary); XCTAssertTrue(bin.text.hasPrefix("00000000  00 01 02 41"), bin.text)
        XCTAssertEqual(BodyFormatter.format(Data(), contentType: nil).text, "")
    }
}

final class SyntaxHighlighterTests: XCTestCase {
    private func kinds(_ text: String, _ language: BodyLanguage) -> [(String, SyntaxHighlighter.Kind)] {
        let ns = text as NSString
        return SyntaxHighlighter.tokens(in: text, language: language).map { (ns.substring(with: $0.range), $0.kind) }
    }

    private func has(_ list: [(String, SyntaxHighlighter.Kind)], _ text: String, _ kind: SyntaxHighlighter.Kind, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(list.contains { $0.0 == text && $0.1 == kind }, "\(text) as \(kind) in \(list)", file: file, line: line)
    }

    func testJSON() {
        let t = kinds(#"{"name": "x", "n": -1.5e3, "ok": true, "v": null}"#, .json)
        has(t, "\"name\"", .key); has(t, "\"x\"", .string); has(t, "-1.5e3", .number); has(t, "true", .keyword); has(t, "null", .keyword)
    }

    func testStringsContainingKeywordsStayStrings() {
        let t = kinds(#"let s = "if else"; // let"#, .swift)
        has(t, "let", .keyword); has(t, "\"if else\"", .string); has(t, "// let", .comment)
        XCTAssertEqual(t.filter { $0.1 == .keyword }.count, 1)
    }

    func testXMLAndHTML() {
        let t = kinds(#"<a href="u" id='i'><!-- c --></a>"#, .html)
        has(t, "<a", .tag); has(t, "href", .attribute); has(t, "\"u\"", .string); has(t, "<!-- c -->", .comment); has(t, "</a", .tag)
    }

    func testHTTPHeadersAndURLEncodedAndCurl() {
        has(kinds("Content-Type: text/plain\nX-A: 1", .http), "Content-Type", .key)
        let form = kinds("a=1&b=two", .urlencoded)
        has(form, "a", .key); has(form, "b", .key); has(form, "two", .string)
        let curl = kinds("curl -X POST 'https://a.b/c' --header 'X: 1'", .curl)
        has(curl, "curl", .keyword); has(curl, "-X", .attribute); has(curl, "--header", .attribute)
    }

    func testCSSGraphQLAndEdgeCases() {
        let css = kinds("a{color:#fff;margin:10px}", .css)
        has(css, "color", .attribute); has(css, "#fff", .number); has(css, "10px", .number)
        let gql = kinds("query Q($id: ID!) { user }", .graphql)
        has(gql, "query", .keyword); has(gql, "$id", .variable)
        XCTAssertTrue(SyntaxHighlighter.tokens(in: "", language: .json).isEmpty)
        XCTAssertTrue(SyntaxHighlighter.tokens(in: "abc", language: .plain).isEmpty)
        let emoji = "{\"k\":\"😀\",\"n\":1}" // UTF-16 ranges must survive surrogate pairs
        has(kinds(emoji, .json), "1", .number)
    }

    func testTokensNeverOverlap() {
        let tokens = SyntaxHighlighter.tokens(in: #"<a b="c d">x</a> /* "q" */"#, language: .html)
        for (a, b) in zip(tokens, tokens.dropFirst()) {
            XCTAssertLessThanOrEqual(a.range.location + a.range.length, b.range.location)
        }
    }
}

final class SyntaxIndexTests: XCTestCase {
    private func tokens(_ text: String, _ language: BodyLanguage, in range: NSRange? = nil) throws -> [(String, SyntaxHighlighter.Kind)] {
        let index = try XCTUnwrap(SyntaxIndex(language: language))
        index.parse(text)
        let ns = text as NSString
        return index.tokens(in: range ?? NSRange(location: 0, length: ns.length)).map { (ns.substring(with: $0.range), $0.kind) }
    }

    private func has(_ list: [(String, SyntaxHighlighter.Kind)], _ text: String, _ kind: SyntaxHighlighter.Kind, line: UInt = #line) {
        XCTAssertTrue(list.contains { $0.0 == text && $0.1 == kind }, "\(text) as \(kind) in \(list)", line: line)
    }

    func testSupportedLanguages() {
        for language in [BodyLanguage.json, .html, .xml, .plist, .css, .javascript] {
            XCTAssertTrue(SyntaxIndex.supports(language))
        }
        XCTAssertFalse(SyntaxIndex.supports(.curl)); XCTAssertNil(SyntaxIndex(language: .graphql))
    }

    func testJSONKeysBeatStrings() throws {
        let t = try tokens(#"{"k": "v", "n": -1.5e3, "b": true, "z": null}"#, .json)
        has(t, "\"k\"", .key); has(t, "\"v\"", .string); has(t, "-1.5e3", .number); has(t, "true", .keyword); has(t, "null", .keyword)
        XCTAssertFalse(t.contains { $0.0 == "\"k\"" && $0.1 == .string })
    }

    func testHTMLCSSAndJavaScript() throws {
        let html = try tokens(#"<a href="u" id=i>x</a><!-- c -->"#, .html)
        has(html, "a", .tag); has(html, "href", .attribute); has(html, "\"u\"", .string); has(html, "<!-- c -->", .comment)
        let css = try tokens("a.b{color:#fff;margin:10px} /* c */", .css)
        has(css, "color", .attribute); has(css, "#fff", .number); has(css, "/* c */", .comment)
        let js = try tokens(#"const x = "s" + 42; // c"#, .javascript)
        has(js, "const", .keyword); has(js, "\"s\"", .string); has(js, "42", .number); has(js, "// c", .comment)
    }

    func testWindowOnlyReturnsWhatIsAskedFor() throws {
        let text = "[" + (0 ..< 2000).map { "{\"id\":\($0),\"name\":\"n\($0)\"}" }.joined(separator: ",") + "]"
        let window = NSRange(location: 20000, length: 400)
        let t = try tokens(text, .json, in: window)
        XCTAssertFalse(t.isEmpty); XCTAssertLessThan(t.count, 100)
    }

    /// The reason for the library: a multi-megabyte body parses once, then a screenful is coloured in milliseconds.
    func testLargeDocument() throws {
        let item = #"{"id":12345,"name":"Ada Lovelace","tags":["a","b",null,true],"score":-1.5e3},"#
        let text = "[" + String(repeating: item, count: 60000) + #"{"end":1}]"# // ~4.6 MB
        let index = try XCTUnwrap(SyntaxIndex(language: .json))
        let parsed = Date(); index.parse(text)
        XCTAssertLessThan(Date().timeIntervalSince(parsed), 10)
        let asked = Date(); let found = index.tokens(in: NSRange(location: 2_000_000, length: 20000))
        XCTAssertGreaterThan(found.count, 100); XCTAssertLessThan(Date().timeIntervalSince(asked), 0.5)
    }
}

final class LargeBodyFormattingTests: XCTestCase {
    func testPrettyPrintsMegabytesQuickly() {
        let item = #"{"id":12345,"name":"Ada \"Lovelace\"","tags":["a","b",null,true],"empty":{},"list":[],"score":-1.5e3},"#
        let text = "[" + String(repeating: item, count: 60000) + #"{"end":1}]"# // ~6 MB
        let start = Date()
        let pretty = JSONFormatter.prettyData(Data(text.utf8))
        XCTAssertLessThan(Date().timeIntervalSince(start), 3)
        XCTAssertGreaterThan(pretty.count, text.utf8.count)
        // Same document after minifying again: nothing was lost or reordered.
        XCTAssertEqual(String(decoding: JSONFormatter.minifyData(pretty), as: UTF8.self), text)
    }

    func testFormatterNoLongerGivesUpAtTwoMegabytes() {
        let text = "[" + String(repeating: #"{"a":1},"#, count: 400_000) + "1]" // ~3 MB
        let formatted = BodyFormatter.format(Data(text.utf8), contentType: "application/json")
        XCTAssertNil(formatted.note); XCTAssertTrue(formatted.text.hasPrefix("[\n  {\n    \"a\": 1"))
    }
}
