import Foundation
import WatcherCore

public extension Flow {
    /// A finished `POST /v1/users?id=7` with JSON both ways, a 201 and a quarter-second duration, for export round trips.
    static func jsonPostFixture() -> Flow {
        var flow = Flow.fixture(
            request: .fixture(
                method: "POST",
                path: "/v1/users?id=7",
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"name":"it's"}"#.utf8)
            ),
            response: .fixture(
                status: 201,
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"ok":true}"#.utf8)
            )
        )
        flow.duration = 0.25
        return flow
    }
}
