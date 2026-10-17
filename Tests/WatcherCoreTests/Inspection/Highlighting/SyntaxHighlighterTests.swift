import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SyntaxHighlighterTests {
    private func spans(_ text: String, _ language: BodyLanguage) -> [HighlightedSpan] {
        SyntaxHighlighter.tokens(in: text, language: language).spans(in: text)
    }

    @Test
    func jsonKeysStringsNumbersAndKeywordsAreColoured() {
        let found = spans(#"{"name": "x", "n": -1.5e3, "ok": true, "v": null}"#, .json)
        #expect(found.contains(.init("\"name\"", .key))); #expect(found.contains(.init("\"x\"", .string)))
        #expect(found.contains(.init("-1.5e3", .number))); #expect(found.contains(.init("true", .keyword)))
        #expect(found.contains(.init("null", .keyword)))
    }

    @Test
    func stringsContainingKeywordsStayStrings() {
        let found = spans(#"let s = "if else"; // let"#, .swift)
        #expect(found.contains(.init("let", .keyword))); #expect(found.contains(.init("\"if else\"", .string)))
        #expect(found.contains(.init("// let", .comment)))
        #expect(found.filter { $0.kind == .keyword }.count == 1)
    }

    @Test
    func htmlTagsAttributesStringsAndCommentsAreColoured() {
        let found = spans(#"<a href="u" id='i'><!-- c --></a>"#, .html)
        #expect(found.contains(.init("<a", .tag))); #expect(found.contains(.init("href", .attribute)))
        #expect(found.contains(.init("\"u\"", .string))); #expect(found.contains(.init("<!-- c -->", .comment)))
        #expect(found.contains(.init("</a", .tag)))
    }

    @Test
    func httpHeadersFormFieldsAndCurlFlagsAreColoured() {
        #expect(spans("Content-Type: text/plain\nX-A: 1", .http).contains(.init("Content-Type", .key)))
        let form = spans("a=1&b=two", .urlencoded)
        #expect(form.contains(.init("a", .key))); #expect(form.contains(.init("b", .key)))
        #expect(form.contains(.init("two", .string)))
        let curl = spans("curl -X POST 'https://a.b/c' --header 'X: 1'", .curl)
        #expect(curl.contains(.init("curl", .keyword))); #expect(curl.contains(.init("-X", .attribute)))
        #expect(curl.contains(.init("--header", .attribute)))
    }

    @Test
    func cssGraphQLAndEdgeCasesAreColoured() {
        let css = spans("a{color:#fff;margin:10px}", .css)
        #expect(css.contains(.init("color", .attribute))); #expect(css.contains(.init("#fff", .number)))
        #expect(css.contains(.init("10px", .number)))
        let gql = spans("query Q($id: ID!) { user }", .graphql)
        #expect(gql.contains(.init("query", .keyword))); #expect(gql.contains(.init("$id", .variable)))
        #expect(SyntaxHighlighter.tokens(in: "", language: .json).isEmpty)
        #expect(SyntaxHighlighter.tokens(in: "abc", language: .plain).isEmpty)
        let emoji = "{\"k\":\"😀\",\"n\":1}"
        #expect(spans(emoji, .json).contains(.init("1", .number)), "UTF-16 ranges must survive surrogate pairs")
    }

    @Test
    func tokensNeverOverlap() {
        let tokens = SyntaxHighlighter.tokens(in: #"<a b="c d">x</a> /* "q" */"#, language: .html)
        for (current, next) in zip(tokens, tokens.dropFirst()) {
            #expect(current.range.location + current.range.length <= next.range.location)
        }
    }
}
