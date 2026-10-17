import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FilterTests {
    private func flow(
        _ method: String = "GET",
        host: String = "api.example.com",
        path: String = "/a",
        status: Int? = 200,
        type: String? = "application/json",
        body: String = "",
        app: String? = nil
    ) -> Flow {
        .fixture(
            request: .fixture(method: method, host: host, path: path, clientApp: app),
            response: status.map { status in
                .fixture(
                    status: status,
                    headers: type.map { [Header("Content-Type", $0)] } ?? [],
                    body: Data(body.utf8)
                )
            }
        )
    }

    @Test
    func emptyFilterIsInactiveAndKeepsEverything() {
        let filter = FlowFilter()
        #expect(!filter.isActive)
        #expect(filter.apply(to: [flow(), flow(status: nil)]).count == 2)
    }

    @Test
    func quickTogglesNarrowTheList() {
        var filter = FlowFilter(); filter.methods = ["POST"]
        #expect(!filter.matches(flow())); #expect(filter.matches(flow("post")))
        filter.reset(); filter.statusClasses = [4, 5]
        #expect(filter.matches(flow(status: 404))); #expect(!filter.matches(flow(status: 200)))
        filter.reset(); filter.errorsOnly = true
        #expect(filter.matches(flow(status: nil))); #expect(filter.matches(flow(status: 500)))
        #expect(!filter.matches(flow()))
        filter.reset(); filter.contentKinds = [.image]
        #expect(filter.matches(flow(type: "image/png"))); #expect(!filter.matches(flow()))
        filter.reset(); filter.starredOnly = true
        var starred = flow(); starred.isStarred = true
        #expect(filter.matches(starred)); #expect(!filter.matches(flow()))
    }

    @Test
    func textSearchLooksOnlyInItsScope() {
        var filter = FlowFilter(); filter.text = "needle"
        #expect(!filter.matches(flow(path: "/x", body: "needle")))
        filter.scope = .body; #expect(filter.matches(flow(body: "a NEEDLE b")))
        filter.scope = .url; #expect(filter.matches(flow(path: "/needle")))
        filter.scope = .all
        var commented = flow(); commented.comment = "needle here"
        #expect(filter.matches(commented)); #expect(!filter.matches(flow()))
    }

    @Test
    func sidebarSelectionIncludesSubdomains() {
        var filter = FlowFilter(); filter.host = "example.com"
        #expect(filter.matches(flow(host: "api.example.com"))); #expect(filter.matches(flow(host: "example.com")))
        #expect(!filter.matches(flow(host: "notexample.com")))
        filter.reset(); filter.app = "Safari"
        #expect(filter.matches(flow(app: "Safari"))); #expect(!filter.matches(flow(app: "curl")))
    }
}
