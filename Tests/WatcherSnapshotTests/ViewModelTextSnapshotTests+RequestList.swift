import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The request list empty, filled and filtered: its rows, the count line and the sidebar groups.
    @MainActor
    struct RequestList {
        private static let flows: [Flow] = [
            .fixture(sequence: 1, host: "api.example.com", status: 200, clientApp: "Safari"),
            .fixture(sequence: 2, host: "api.example.com", status: 404, clientApp: "curl", starred: true),
            .fixture(sequence: 3, host: "cdn.example.com", status: 500, clientApp: "Safari"),
            .fixture(sequence: 4, host: "ads.tracker.net", status: nil, clientApp: "Slack"),
        ]

        private func describe(_ list: FlowListViewModel) -> String {
            let rows = list.visibleFlows.map { flow in
                let status = flow.response.map { String($0.status) } ?? "—"
                return "#\(flow.sequence) \(flow.request.method) \(flow.request.host)\(flow.request.path) \(status)"
            }
            let counts = list.counts
            let groups = [
                "starred \(counts.starred) · errors \(counts.errors) · websocket \(counts.webSocket)",
                "apps: " + counts.apps.map { "\($0.name) (\($0.count))" }.joined(separator: ", "),
                "domains: " + counts.domains.map { "\($0.name) (\($0.count))" }.joined(separator: ", "),
            ]
            return ([list.countText] + rows + groups).joined(separator: "\n")
        }

        private func list(_ flows: [Flow]) -> FlowListViewModel {
            let store = FlowStore()
            store.load(flows)
            let list = FlowListViewModel(store: store, sleep: sleepUntilCancelled)
            list.syncFromStore()
            return list
        }

        @Test
        func anEmptyList() {
            assertSnapshot(of: describe(list([])), as: .lines)
        }

        @Test
        func aFilledList() {
            assertSnapshot(of: describe(list(Self.flows)), as: .lines)
        }

        @Test
        func aListFilteredByStatusAndSidebar() {
            let list = list(Self.flows)
            list.query.statusClasses = [4, 5]
            let byStatus = describe(list)
            list.query.reset()
            list.sidebar = .domain("example.com")
            assertSnapshot(of: byStatus + "\n---\n" + describe(list), as: .lines)
        }
    }
}
