/// A debugging tool (Block List, Map Local, ...) hooked into the proxy pipeline.
public protocol Tool: Sendable {
    var name: String { get }
    func intercept(request: inout RequestRecord) async -> RequestDecision
    func intercept(response: inout ResponseRecord, for request: RequestRecord) async
    /// True when the tool needs the whole response body, which rules out streaming it to the client.
    var inspectsResponses: Bool { get }
    /// True when the tool reads or edits the request body, which rules out streaming an upload through.
    var needsRequestBody: Bool { get }
}

public extension Tool {
    func intercept(request _: inout RequestRecord) async -> RequestDecision {
        .forward
    }

    func intercept(response _: inout ResponseRecord, for _: RequestRecord) async {}
    var inspectsResponses: Bool {
        false
    }

    var needsRequestBody: Bool {
        false
    }
}
