import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct BreakpointToolTests {
    private let center = BreakpointCenter()

    private func tool(onRequest: Bool = true, onResponse: Bool = true, pattern: String = "*") -> BreakpointTool {
        let matching = MatchingRule(pattern: pattern)
        let rule = BreakpointRule(matching: matching, onRequest: onRequest, onResponse: onResponse)
        return BreakpointTool(rules: [rule], center: center)
    }

    /// Runs `work` while the center holds one message, and resolves that hold with `resolution`.
    private func resolving<T: Sendable>(
        _ resolution: BreakpointCenter.Resolution,
        during work: @escaping @Sendable () async -> T
    ) async throws -> T {
        let task = Task { await work() }
        try #require(await eventually { center.pending.count == 1 })
        let hit = try #require(center.pending.first)
        center.resolve(hit.id, with: resolution)
        return await task.value
    }

    @Test
    func aRequestIsHeldAndContinuesWithTheEdit() async throws {
        let tool = tool()
        let edited = RequestRecord.fixture(path: "/edited")
        let (decision, request) = try await resolving(.proceed(request: edited, response: nil)) {
            var request = RequestRecord.fixture(path: "/original")
            return await (tool.intercept(request: &request), request)
        }
        guard case .forward = decision else { Issue.record("expected forward"); return }
        #expect(request.path == "/edited")
    }

    @Test
    func anAbortedRequestIsAnswered502() async throws {
        let tool = tool()
        let decision = try await resolving(.abort) {
            var request = RequestRecord.fixture()
            return await tool.intercept(request: &request)
        }
        guard case let .respond(response) = decision else { Issue.record("expected an answer"); return }
        #expect(response.status == 502)
    }

    @Test
    func aResponseIsHeldAndContinuesWithTheEdit() async throws {
        let tool = tool()
        let edited = ResponseRecord.fixture(status: 418)
        let response = try await resolving(.proceed(request: .fixture(), response: edited)) {
            var response = ResponseRecord.fixture(status: 200)
            await tool.intercept(response: &response, for: .fixture())
            return response
        }
        #expect(response.status == 418)
    }

    @Test
    func aResponseResolvedWithoutAnEditStaysAsItWas() async throws {
        let tool = tool()
        let response = try await resolving(.proceed(request: .fixture(), response: nil)) {
            var response = ResponseRecord.fixture(status: 200)
            await tool.intercept(response: &response, for: .fixture())
            return response
        }
        #expect(response.status == 200)
    }

    @Test
    func anAbortedResponseBecomes502() async throws {
        let tool = tool()
        let response = try await resolving(.abort) {
            var response = ResponseRecord.fixture(status: 200)
            await tool.intercept(response: &response, for: .fixture())
            return response
        }
        #expect(response.status == 502)
    }

    @Test
    func aPhaseThatIsNotSelectedOrAURLThatDoesNotMatchIsNeverHeld() async {
        var request = RequestRecord.fixture(path: "/x")
        var response = ResponseRecord.fixture()
        _ = await tool(onRequest: false).intercept(request: &request)
        await tool(onResponse: false).intercept(response: &response, for: request)
        _ = await tool(pattern: "other.test/*").intercept(request: &request)
        await tool(pattern: "other.test/*").intercept(response: &response, for: request)
        #expect(center.pending.isEmpty)
    }

    @Test(arguments: [
        (true, false, true, false), (false, true, false, true), (true, true, true, true), (false, false, false, false),
    ])
    func theToolNeedsTheBodiesItHolds(onRequest: Bool, onResponse: Bool, needsBody: Bool, inspects: Bool) {
        let tool = tool(onRequest: onRequest, onResponse: onResponse)
        #expect(tool.needsRequestBody == needsBody)
        #expect(tool.inspectsResponses == inspects)
    }
}
