import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FlowGroupingTests {
    private func flow(host: String = "api.example.com", app: String? = nil, kind: ClientKind? = nil) -> Flow {
        .fixture(
            request: .fixture(host: host, path: "/a", clientApp: app, clientKind: kind),
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
            domains.first == FlowGroup(name: "example.com", count: 3, kind: nil),
            "a.example.com, b.example.com and the Safari flow's api.example.com"
        )
        #expect(domains.contains(FlowGroup(name: "bbc.co.uk", count: 1, kind: nil)))
        #expect(domains.contains(FlowGroup(name: "10.0.0.1", count: 1, kind: nil)))
        #expect(FlowGrouping.apps(flows) == [FlowGroup(name: "Safari", count: 1, kind: .app)])
    }

    @Test
    func appsCarryTheirKindAndRecordsWithoutOneCountAsApps() {
        let flows = [
            flow(app: "Chrome", kind: .app), flow(app: "Chrome", kind: .app), flow(app: "curl", kind: .tool),
            flow(app: "trustd", kind: .service), flow(app: "10.0.0.9", kind: .device), flow(app: "Old"),
        ]
        #expect(FlowGrouping.apps(flows) == [
            FlowGroup(name: "Chrome", count: 2, kind: .app),
            FlowGroup(name: "10.0.0.9", count: 1, kind: .device),
            FlowGroup(name: "Old", count: 1, kind: .app),
            FlowGroup(name: "curl", count: 1, kind: .tool),
            FlowGroup(name: "trustd", count: 1, kind: .service),
        ])
    }
}
