import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FlowGroupingTests {
    private func flow(host: String = "api.example.com", app: String? = nil) -> Flow {
        .fixture(
            request: .fixture(host: host, path: "/a", clientApp: app),
            response: .fixture(headers: [Header("Content-Type", "application/json")])
        )
    }

    @Test
    func groupsByRegistrableDomainAndByApp() {
        let flows = [
            flow(host: "a.example.com"),
            flow(host: "b.example.com"),
            flow(host: "x.bbc.co.uk"),
            flow(host: "10.0.0.1"),
            flow(app: "Safari"),
        ]
        let domains = FlowGrouping.domains(flows)
        #expect(
            domains.first == FlowGroup(name: "example.com", count: 3),
            "a.example.com, b.example.com and the Safari flow's api.example.com"
        )
        #expect(domains.contains(FlowGroup(name: "bbc.co.uk", count: 1)))
        #expect(domains.contains(FlowGroup(name: "10.0.0.1", count: 1)))
        #expect(FlowGrouping.apps(flows) == [FlowGroup(name: "Safari", count: 1)])
    }
}
