import Foundation
import WatcherCore

public extension Flow {
    /// `state` defaults to what the response implies: completed with one, failed without.
    static func fixture(
        sequence: Int = 1,
        request: RequestRecord = .fixture(),
        response: ResponseRecord? = .fixture(),
        state: State? = nil,
        starred: Bool = false,
        duration: TimeInterval? = nil,
        timeToFirstByte: TimeInterval? = nil
    ) -> Flow {
        var flow = Flow(sequence: sequence, request: request)
        flow.response = response
        flow.state = state ?? (response == nil ? .failed : .completed)
        flow.isStarred = starred
        flow.duration = duration
        flow.timeToFirstByte = timeToFirstByte
        return flow
    }

    /// One row of a traffic list: its own path `/<sequence>`, and a nil `status` for a request that got no answer.
    static func fixture(
        sequence: Int,
        host: String = "api.example.com",
        status: Int?,
        body: Data = Data(),
        clientApp: String? = nil,
        clientKind: ClientKind? = nil,
        starred: Bool = false
    ) -> Flow {
        fixture(
            sequence: sequence,
            request: .fixture(host: host, path: "/\(sequence)", clientApp: clientApp, clientKind: clientKind),
            response: status.map { .fixture(status: $0, body: body) },
            starred: starred
        )
    }
}
