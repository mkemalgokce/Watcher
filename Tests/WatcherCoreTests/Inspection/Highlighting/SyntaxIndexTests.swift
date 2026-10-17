import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .serialized)
struct SyntaxIndexTests {
    private func spans(_ text: String, _ language: BodyLanguage, in range: NSRange? = nil) throws -> [HighlightedSpan] {
        let index = try #require(SyntaxIndex(language: language))
        index.parse(text)
        return index.tokens(in: range ?? NSRange(location: 0, length: (text as NSString).length)).spans(in: text)
    }

    @Test(arguments: [BodyLanguage.json, .html, .xml, .plist, .css, .javascript])
    func supportsTheTreeSitterLanguages(_ language: BodyLanguage) {
        #expect(SyntaxIndex.supports(language))
    }

    @Test
    func unsupportedLanguagesHaveNoIndex() {
        #expect(!SyntaxIndex.supports(.curl)); #expect(SyntaxIndex(language: .graphql) == nil)
    }

    @Test
    func jsonKeysBeatStrings() throws {
        let found = try spans(#"{"k": "v", "n": -1.5e3, "b": true, "z": null}"#, .json)
        #expect(found.contains(.init("\"k\"", .key))); #expect(found.contains(.init("\"v\"", .string)))
        #expect(found.contains(.init("-1.5e3", .number))); #expect(found.contains(.init("true", .keyword)))
        #expect(found.contains(.init("null", .keyword)))
        #expect(!found.contains(.init("\"k\"", .string)))
    }

    @Test
    func htmlCSSAndJavaScript() throws {
        let html = try spans(#"<a href="u" id=i>x</a><!-- c -->"#, .html)
        #expect(html.contains(.init("a", .tag))); #expect(html.contains(.init("href", .attribute)))
        #expect(html.contains(.init("\"u\"", .string))); #expect(html.contains(.init("<!-- c -->", .comment)))
        let css = try spans("a.b{color:#fff;margin:10px} /* c */", .css)
        #expect(css.contains(.init("color", .attribute))); #expect(css.contains(.init("#fff", .number)))
        #expect(css.contains(.init("/* c */", .comment)))
        let script = try spans(#"const x = "s" + 42; // c"#, .javascript)
        #expect(script.contains(.init("const", .keyword))); #expect(script.contains(.init("\"s\"", .string)))
        #expect(script.contains(.init("42", .number))); #expect(script.contains(.init("// c", .comment)))
    }

    @Test
    func windowOnlyReturnsWhatIsAskedFor() throws {
        let text = "[" + (0 ..< 2000).map { "{\"id\":\($0),\"name\":\"n\($0)\"}" }.joined(separator: ",") + "]"
        let window = NSRange(location: 20000, length: 400)
        let found = try spans(text, .json, in: window)
        #expect(!found.isEmpty); #expect(found.count < 100)
    }

    /// The reason for the library: a multi-megabyte body parses once, then a screenful is coloured in milliseconds.
    @Test(.tags(.timing))
    func largeDocumentParsesOnceAndColoursAWindowQuickly() throws {
        let item = #"{"id":12345,"name":"Ada Lovelace","tags":["a","b",null,true],"score":-1.5e3},"#
        let text = "[" + String(repeating: item, count: 60000) + #"{"end":1}]"# // ~4.6 MB
        let index = try #require(SyntaxIndex(language: .json))
        let parsed = Date(); index.parse(text)
        #expect(Date().timeIntervalSince(parsed) < 10)
        let asked = Date(); let found = index.tokens(in: NSRange(location: 2_000_000, length: 20000))
        #expect(found.count > 100); #expect(Date().timeIntervalSince(asked) < 0.5)
    }
}
