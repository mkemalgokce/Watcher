import Foundation
import Testing
@testable import WatcherCore

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct URLComponentsOriginFormTests {
    @Test(arguments: [
        ("http://a.test", "/"), ("http://a.test/", "/"), ("http://a.test?q=1", "/?q=1"),
        ("http://a.test/x?q=1&r=%20", "/x?q=1&r=%20"), ("http://a.test/a%20b", "/a%20b"), ("http://a.test/x?", "/x?"),
        ("http://[::1]:80/x#frag", "/x"),
    ])
    func originFormKeepsTheEncodedPathAndQuery(url: String, expected: String) throws {
        #expect(try #require(URLComponents(string: url)).originForm == expected)
    }
}
