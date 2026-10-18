import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// What the inspector shows for a JSON exchange: each side's sections and size line, and the body summary.
    @MainActor
    struct Inspector {
        @Test
        func aJSONExchange() {
            let body = Data(#"{"user":{"id":42,"name":"Ada"}}"#.utf8)
            let flow = Flow.fixture(
                request: .fixture(
                    method: "POST", path: "/v1/users?page=2",
                    headers: [Header("Content-Type", "application/json"), Header("Cookie", "a=1; b=2")], body: body
                ),
                response: .fixture(status: 201, headers: [Header("Content-Type", "application/json")], body: body)
            )
            let text = MessageSide.allCases.map { side in
                let panel = MessagePanelViewModel(flow: flow, side: side, previewersActive: false, embedded: [])
                let sections = panel.available.map { "\($0.rawValue)\(panel.count($0).map { " (\($0))" } ?? "")" }
                let chosen = panel.section(chosen: "Body").rawValue
                let prepared = BodyRendering.prepare(
                    flow.body(side), contentType: "application/json", mode: .pretty, sortKeys: true
                )
                let summary = BodyRendering.summary(mode: .pretty, richKind: nil, prepared: prepared)
                return "\(side.rawValue): \(sections.joined(separator: ", ")) · \(panel.detail)\n"
                    + "  shows \(chosen) · \(summary)\n" + prepared.text
            }
            assertSnapshot(of: text.joined(separator: "\n"), as: .lines)
        }
    }
}
