import Foundation
import WatcherCore

public extension Flow {
    /// `state` defaults to what the response implies: completed with one, failed without.
    static func fixture(
        sequence: Int = 1,
        request: RequestRecord = .fixture(),
        response: ResponseRecord? = .fixture(),
        state: State? = nil,
        starred: Bool = false
    ) -> Flow {
        var flow = Flow(sequence: sequence, request: request)
        flow.response = response
        flow.state = state ?? (response == nil ? .failed : .completed)
        flow.isStarred = starred
        return flow
    }
}
