import Testing
@testable import WatcherCore

/// The reason phrase the inspector shows next to a status code.
struct HTTPStatusTests {
    @Test
    func reasonPhrases() {
        #expect(HTTPStatus.reason(200) == "OK")
        #expect(HTTPStatus.reason(404) == "Not Found")
        #expect(HTTPStatus.reason(502) == "Bad Gateway")
        #expect(!HTTPStatus.reason(299).isEmpty)
    }
}
