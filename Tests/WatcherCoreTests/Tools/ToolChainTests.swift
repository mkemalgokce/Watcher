import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ToolChainTests {
    /// Logs each time it runs, and changes the request or the response when told to.
    private struct Spy: Tool {
        let name: String
        let log: LockedBox<[String]>
        var decision: RequestDecision = .forward
        var stampsRequest = false
        var stampsResponse = false
        var inspectsResponses = false
        var needsRequestBody = false

        func intercept(request: inout RequestRecord) async -> RequestDecision {
            log.mutate { $0.append(name) }
            if stampsRequest {
                request.headers.set("X-\(name)", "1")
            }
            return decision
        }

        func intercept(response: inout ResponseRecord, for _: RequestRecord) async {
            log.mutate { $0.append("\(name) response") }
            if stampsResponse {
                response.headers.set("X-\(name)", "1")
            }
        }
    }

    private let log = LockedBox<[String]>([])

    private func spy(_ name: String, configure: (inout Spy) -> Void = { _ in }) -> Spy {
        var spy = Spy(name: name, log: log)
        configure(&spy)
        return spy
    }

    @Test
    func aToolThatForwardsTheRequestUntouchedIsNotNamed() async {
        let chain = ToolChain([spy("Quiet"), spy("Loud") { $0.stampsRequest = true }])
        var request = RequestRecord.fixture()
        let (decision, applied) = await chain.applyRequest(&request)
        guard case .forward = decision else { Issue.record("expected the request to be forwarded"); return }
        #expect(applied == ["Loud"])
        #expect(log.value == ["Quiet", "Loud"])
    }

    @Test(arguments: [
        RequestDecision.block(hidden: false), .respond(ResponseRecord(status: 200, headers: [], body: Data())),
    ])
    func theFirstToolToBlockOrAnswerEndsTheChain(decision: RequestDecision) async {
        let chain = ToolChain([spy("First"), spy("Gate") { $0.decision = decision }, spy("Never")])
        var request = RequestRecord.fixture()
        let (_, applied) = await chain.applyRequest(&request)
        #expect(applied == ["Gate"])
        #expect(log.value == ["First", "Gate"])
    }

    @Test
    func laterToolsSeeWhatEarlierOnesChanged() async {
        let chain = ToolChain([spy("A") { $0.stampsRequest = true }, spy("B") { $0.stampsRequest = true }])
        var request = RequestRecord.fixture()
        _ = await chain.applyRequest(&request)
        #expect(request.headers.value(for: "X-A") == "1" && request.headers.value(for: "X-B") == "1")
    }

    @Test
    func aToolIsNamedForAResponseOnlyWhenItChangedIt() async {
        let chain = ToolChain([spy("Quiet"), spy("Loud") { $0.stampsResponse = true }])
        var response = ResponseRecord.fixture()
        let applied = await chain.applyResponse(&response, for: .fixture())
        #expect(applied == ["Loud"])
        #expect(log.value == ["Quiet response", "Loud response"])
    }

    @Test(arguments: [(false, false), (true, false), (false, true), (true, true)])
    func theChainNeedsWhatAnyToolNeeds(inspects: Bool, needsBody: Bool) {
        let chain = ToolChain([
            spy("Plain"),
            spy("Needy") { $0.inspectsResponses = inspects; $0.needsRequestBody = needsBody },
        ])
        #expect(chain.inspectsResponses == inspects)
        #expect(chain.needsRequestBody == needsBody)
    }

    @Test
    func replacingTheToolsTakesEffectForTheNextRequest() async {
        let chain = ToolChain([spy("Old")])
        chain.set([spy("New")])
        var request = RequestRecord.fixture()
        _ = await chain.applyRequest(&request)
        #expect(log.value == ["New"])
    }

    @Test
    func anEmptyChainForwardsAndNamesNothing() async {
        var request = RequestRecord.fixture()
        let (decision, applied) = await ToolChain().applyRequest(&request)
        guard case .forward = decision else { Issue.record("expected the request to be forwarded"); return }
        #expect(applied.isEmpty)
    }
}
