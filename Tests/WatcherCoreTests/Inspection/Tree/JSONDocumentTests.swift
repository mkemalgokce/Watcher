import Testing
@testable import WatcherCore

/// Whether a piece of text, such as a form field or a header value, is a whole JSON object or array worth opening.
@Suite(.tags(.unit))
struct JSONDocumentTests {
    @Test(arguments: [#"{"a":1}"#, "[1,2]", "  {\"a\": [1]}\n", "{}", "[]"])
    func objectsAndArraysAreDocuments(text: String) {
        #expect(JSONTree.isDocument(text))
    }

    @Test(arguments: ["", "42", "true", "null", #""text""#, "[draft]", "{broken", "hello world", "{a:1}", "[1,]"])
    func everythingElseIsNot(text: String) {
        #expect(!JSONTree.isDocument(text))
    }

    @Test
    func aHugeValueIsNotParsedJustToDecideOnAnIcon() {
        let huge = "[" + String(repeating: "1,", count: JSONTree.detectionLimit) + "1]"
        #expect(!JSONTree.isDocument(huge))
    }
}
