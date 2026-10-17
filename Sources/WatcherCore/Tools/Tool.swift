import Foundation

public enum RequestDecision: Sendable {
    case forward
    case respond(ResponseRecord)
    /// `hidden` keeps the blocked request out of the session list.
    case block(hidden: Bool)
}

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

/// Ordered, thread-safe list of enabled tools.
public final class ToolChain: @unchecked Sendable {
    private let lock = NSLock()
    private var tools: [Tool]

    public init(_ tools: [Tool] = []) {
        self.tools = tools
    }

    public func set(_ tools: [Tool]) {
        lock.withLock { self.tools = tools }
    }

    var inspectsResponses: Bool {
        snapshot.contains { $0.inspectsResponses }
    }

    var needsRequestBody: Bool {
        snapshot.contains { $0.needsRequestBody }
    }

    private var snapshot: [Tool] {
        lock.withLock { tools }
    }

    /// Runs every tool; stops at the first one that blocks or answers by itself.
    func applyRequest(_ request: inout RequestRecord) async -> (RequestDecision, [String]) {
        var applied: [String] = []
        for tool in snapshot {
            let before = request
            let decision = await tool.intercept(request: &request)
            if case .forward = decision {
                if request != before {
                    applied.append(tool.name)
                }
            } else {
                applied.append(tool.name)
                return (decision, applied)
            }
        }
        return (.forward, applied)
    }

    func applyResponse(_ response: inout ResponseRecord, for request: RequestRecord) async -> [String] {
        var applied: [String] = []
        for tool in snapshot {
            let before = response
            await tool.intercept(response: &response, for: request)
            if response != before {
                applied.append(tool.name)
            }
        }
        return applied
    }
}
