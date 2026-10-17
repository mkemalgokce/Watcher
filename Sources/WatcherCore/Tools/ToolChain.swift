import Foundation

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
