import WatcherCore

/// A tool that decides every request the same way and can stamp responses, so the proxy's handling of each outcome can
/// be checked without real rules.
public struct ToolStub: Tool {
    public let name: String
    public let inspectsResponses: Bool
    private let decision: RequestDecision
    private let responseHeader: Header?

    public init(
        name: String = "Stub",
        decision: RequestDecision = .forward,
        inspectsResponses: Bool = false,
        responseHeader: Header? = nil
    ) {
        self.name = name; self.decision = decision
        self.inspectsResponses = inspectsResponses; self.responseHeader = responseHeader
    }

    public func intercept(request _: inout RequestRecord) async -> RequestDecision {
        decision
    }

    public func intercept(response: inout ResponseRecord, for _: RequestRecord) async {
        if let responseHeader {
            response.headers.append(responseHeader)
        }
    }
}
