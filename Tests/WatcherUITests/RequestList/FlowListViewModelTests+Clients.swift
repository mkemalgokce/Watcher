import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension FlowListViewModelTests {
    /// The sidebar's rows by kind of client, and hiding the system services.
    @MainActor
    struct Clients {
        private func list() -> FlowListViewModel {
            FlowListViewModel(store: FlowStore(), sleep: sleepUntilCancelled)
        }

        private func fill(_ list: FlowListViewModel) {
            [
                Flow.fixture(sequence: 1, status: 200, clientApp: "Chrome", clientKind: .app),
                .fixture(sequence: 2, status: 200, clientApp: "Old"),
                .fixture(sequence: 3, status: 200, clientApp: "curl", clientKind: .tool),
                .fixture(sequence: 4, status: 200, clientApp: "trustd", clientKind: .service),
                .fixture(sequence: 5, status: 200, clientApp: "10.0.0.9", clientKind: .device),
                .fixture(sequence: 6, status: 200),
            ].forEach { list.enqueue(.added($0)) }
            list.flushEvents()
        }

        @Test(arguments: [
            (ClientKind.app, ["Chrome", "Old"]), (.tool, ["curl"]), (.service, ["trustd"]), (.device, ["10.0.0.9"]),
        ])
        func sidebarRowsAreSplitByKindWithOldRecordsAmongTheApps(kind: ClientKind, names: [String]) {
            let list = list()
            fill(list)
            #expect(list.groups(of: kind).map(\.name).sorted() == names)
        }

        @Test
        func systemServicesStartCollapsed() {
            #expect(!list().expandsSystemServices)
        }

        @Test
        func hidingSystemServicesRemovesTheirFlowsAndTheirSidebarSection() {
            let list = list()
            fill(list)
            #expect(list.visibleFlows.count == 6)
            list.hidesSystemServices = true
            #expect(list.visibleFlows.map(\.sequence) == [1, 2, 3, 5, 6])
            #expect(list.groups(of: .service).isEmpty)
            #expect(list.groups(of: .tool).count == 1, "only services are hidden")
            list.hidesSystemServices = false
            #expect(list.visibleFlows.count == 6)
            #expect(list.groups(of: .service).count == 1)
        }
    }
}
