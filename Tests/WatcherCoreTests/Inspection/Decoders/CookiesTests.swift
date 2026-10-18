import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CookiesTests {
    @Test
    func listsRequestCookiesThenResponseCookiesWithTheirAttributes() {
        let flow = Flow.fixture(
            request: .fixture(host: "h", headers: [Header("Cookie", "a=1; b=two=2")]),
            response: .fixture(headers: [
                Header("Set-Cookie", "sid=xyz; Path=/; HttpOnly; Secure"),
                Header("set-cookie", "t=1; SameSite=Lax"),
            ]),
            state: .pending
        )
        let cookies = Cookies.entries(for: flow)
        #expect(cookies.map(\.name) == ["a", "b", "sid", "t"])
        #expect(cookies[1].value == "two=2")
        #expect(cookies[2].isSecure && cookies[2].isHttpOnly); #expect(!cookies[3].isSecure)
        #expect(cookies[3].attributes == ["SameSite=Lax"])
    }
}
