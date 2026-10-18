import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network))
struct BreakpointToolTests {
    @Test
    func aResponseBreakpointHoldsAnEmptyBody() async throws {
        try await withHarness(configure: {
            $0.breakpoints = breakpoint("*/empty", onRequest: false, onResponse: true)
        }) { harness in
            async let pending = harness.get("/empty")
            await waitForHeldRequests(1, in: harness)
            let hit = try #require(harness.engine.breakpoints.pending.first)
            #expect(hit.response?.status == 200)
            harness.engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: hit.response))
            let result = try await pending
            #expect(result.status == 200); #expect(result.body == "")
        }
    }

    @Test
    func aRequestIsHeldUntilResolvedAndTheEditIsApplied() async throws {
        try await withHarness(configure: { $0.breakpoints = breakpoint("*/bp") }) { harness in
            async let pending = harness.get("/bp")
            await waitForHeldRequests(1, in: harness)
            var hit = try #require(harness.engine.breakpoints.pending.first)
            hit.request.path = "/edited"
            harness.engine.breakpoints.resolve(hit.id, with: .proceed(request: hit.request, response: nil))
            let result = try await pending
            #expect(result.body.hasPrefix("GET /edited"), "\(result.body)")
        }
    }

    @Test
    func abortAnswersTheHeldRequestWith502() async throws {
        try await withHarness(configure: { $0.breakpoints = breakpoint("*/bp") }) { harness in
            async let pending = harness.get("/bp")
            await waitForHeldRequests(1, in: harness)
            try harness.engine.breakpoints.resolve(#require(harness.engine.breakpoints.pending.first).id, with: .abort)
            let aborted = try await pending
            #expect(aborted.status == 502)
        }
    }

    @Test
    func abortAllAnswersEveryHeldRequestWith502() async throws {
        try await withHarness(configure: { $0.breakpoints = breakpoint("*/bp*") }) { harness in
            async let first = harness.get("/bp?1"), second = harness.get("/bp?2")
            await waitForHeldRequests(2, in: harness, timeout: 6)
            #expect(harness.engine.breakpoints.pending.count == 2)
            harness.engine.breakpoints.abortAll()
            let results = try await [first.status, second.status]
            #expect(results == [502, 502])
            #expect(harness.engine.breakpoints.pending.isEmpty)
        }
    }

    private func breakpoint(
        _ pattern: String,
        onRequest: Bool = true,
        onResponse: Bool = false
    ) -> RuleSet<BreakpointRule> {
        RuleSet(isEnabled: true, rules: [
            BreakpointRule(matching: MatchingRule(pattern: pattern), onRequest: onRequest, onResponse: onResponse),
        ])
    }

    private func waitForHeldRequests(_ count: Int, in harness: Harness, timeout: TimeInterval = 5) async {
        _ = await eventually(timeout: timeout, poll: .milliseconds(100)) {
            harness.engine.breakpoints.pending.count >= count
        }
    }
}
