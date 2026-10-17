import Foundation
import WatcherCore

public extension Flow {
    /// A pending `POST /v1/x?a=1,2` from Google Chrome that two tools touched: a comma in the URL, a quote and a `#` in
    /// the body, for exporters and code generators that must escape them.
    static func annotatedJSONPostFixture() -> Flow {
        let json = [Header("Content-Type", "application/json")]
        var flow = Flow.fixture(
            sequence: 3,
            request: .fixture(
                method: "POST",
                path: "/v1/x?a=1,2",
                headers: json,
                body: Data(#"{"k":"it's #1"}"#.utf8),
                clientApp: "Google Chrome"
            ),
            response: .fixture(headers: json, body: Data("ok".utf8)),
            state: .pending
        )
        flow.duration = 0.25
        flow.appliedTools = ["Map Local", "Scripting"]
        return flow
    }
}
