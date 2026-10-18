import AsyncHTTPClient
import Foundation

/// The recorded flow of one request the proxy serves, and the ways it can end.
struct FlowExchange: Sendable {
    let store: FlowStore
    let flowID: UUID
    /// Whether answers name the tools that changed them in `X-Watcher-Applied`.
    let marksTools: Bool
    let now: @Sendable () -> Date
    private let started: Date

    init(store: FlowStore, flowID: UUID, marksTools: Bool, now: @escaping @Sendable () -> Date) {
        self.store = store; self.flowID = flowID; self.marksTools = marksTools; self.now = now
        started = now()
    }

    /// Records the whole answer and hands it to the client.
    func finish(
        _ request: RequestRecord,
        _ response: ResponseRecord,
        state: Flow.State,
        tools: [String],
        error: String? = nil
    ) -> ProxyServer.ClientResponse {
        .buffered(record(request, response, state: state, tools: tools, error: error))
    }

    /// The recorded answer to a request the tools blocked or answered themselves; nil when they let it through.
    func answer(_ decision: RequestDecision, to request: RequestRecord, tools: [String]) -> ResponseRecord? {
        switch decision {
        case .forward:
            return nil
        case let .block(hidden):
            if hidden {
                store.discard(flowID)
            }
            return record(request, ProxyServer.message(403, "Blocked by Watcher"), state: .blocked, tools: tools)
        case let .respond(response):
            return record(request, response, state: .completed, tools: tools)
        }
    }

    private func record(
        _ request: RequestRecord,
        _ response: ResponseRecord,
        state: Flow.State,
        tools: [String],
        error: String? = nil
    ) -> ResponseRecord {
        let response = marked(response, tools)
        store.update(flowID) {
            $0.request = request; $0.response = response; $0.state = state
            $0.error = error; $0.appliedTools = tools
            $0.duration = now().timeIntervalSince(started)
        }
        return response
    }

    /// Records the head now and the captured body once the relay ends.
    func stream(
        _ request: RequestRecord,
        head: ResponseRecord,
        body: HTTPClientResponse.Body,
        tools: [String]
    ) -> ProxyServer.ClientResponse {
        let head = marked(head, tools)
        store.update(flowID) { $0.request = request; $0.response = head; $0.appliedTools = tools }
        return .streamed(head: head, body: body) { [self] captured, error in
            store.update(flowID) {
                $0.response?.body = captured
                $0.state = error == nil ? .completed : .failed
                $0.error = error.map { "\($0)" }
                $0.duration = now().timeIntervalSince(started)
            }
        }
    }

    private func marked(_ response: ResponseRecord, _ tools: [String]) -> ResponseRecord {
        guard marksTools, !tools.isEmpty else { return response }
        var copy = response
        copy.headers.set("X-Watcher-Applied", tools.joined(separator: ", "))
        return copy
    }
}
