import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Comparing a request with a base: the states the Compare window shows and what each subject compares.
@MainActor
@Suite(.tags(.unit))
struct DiffViewModelTests {
    private static let json = [Header("Content-Type", "application/json")]

    @Test
    func stateShowsAMissingBaseTheSameFlowOrTheChanges() async {
        let viewModel = DiffViewModel()
        let base = Flow.fixture(sequence: 1, response: .fixture(headers: Self.json, body: Data(#"{"a":1}"#.utf8)))
        let changed = Flow.fixture(sequence: 2, response: .fixture(headers: Self.json, body: Data(#"{"a":2}"#.utf8)))
        let same = Flow.fixture(sequence: 3, response: .fixture(headers: Self.json, body: Data(#"{"a":1}"#.utf8)))
        await viewModel.update(base: nil, current: base)
        #expect(viewModel.state == .noBase)
        await viewModel.update(base: base, current: base)
        #expect(viewModel.state == .sameFlow)
        await viewModel.update(base: base, current: changed)
        guard case let .ready(changes) = viewModel.state else {
            Issue.record("\(viewModel.state)")
            return
        }
        #expect(changes.added == 1); #expect(changes.removed == 1)
        await viewModel.update(base: base, current: same)
        guard case let .ready(comparison) = viewModel.state else {
            Issue.record("\(viewModel.state)")
            return
        }
        #expect(comparison.isIdentical)
    }

    @Test
    func eachSubjectComparesItsOwnPartOfTheFlows() {
        let base = Flow.fixture(sequence: 1, request: .fixture(headers: [Header("X-Trace", "1")]))
        let current = Flow.fixture(sequence: 2, request: .fixture(headers: [Header("X-Trace", "2")]))
        #expect(DiffViewModel.text(base, .headers).contains("X-Trace: 1"))
        let headers = (DiffViewModel.text(base, .headers), DiffViewModel.text(current, .headers))
        #expect(!DiffViewModel.compare(headers.0, headers.1).isIdentical)
        let requestBodies = (DiffViewModel.text(base, .requestBody), DiffViewModel.text(current, .requestBody))
        #expect(DiffViewModel.compare(requestBodies.0, requestBodies.1).isIdentical)
        #expect(DiffViewModel.text(.fixture(sequence: 3, response: nil), .responseBody) == "")
    }

    @Test
    func suggestedBaseIsTheEarlierCallToTheSameEndpoint() {
        let flows = ["/v1/users?page=1", "/v1/other", "/v1/users?page=2", "/v1/users"].enumerated().map {
            Flow.fixture(sequence: $0.offset + 1, request: .fixture(path: $0.element))
        }
        #expect(DiffViewModel.suggestedBase(for: flows[3], in: flows)?.sequence == 3)
        #expect(DiffViewModel.suggestedBase(for: flows[0], in: flows) == nil, "nothing earlier")
        #expect(DiffViewModel.suggestedBase(for: flows[1], in: flows) == nil, "no other call to that path")
    }

    private func flow(_ sequence: Int, body: String, status: Int = 200) -> Flow {
        .fixture(
            sequence: sequence,
            response: .fixture(status: status, headers: Self.json, body: Data(body.utf8))
        )
    }

    @Test
    func aBodyChangingToOtherContentOfTheSameSizeIsComparedAgain() async {
        let viewModel = DiffViewModel()
        let base = flow(1, body: #"{"a":1}"#)
        let current = flow(2, body: #"{"a":2}"#)
        await viewModel.update(base: base, current: current)
        var edited = current
        edited.response = flow(2, body: #"{"a":1}"#).response
        await viewModel.update(base: base, current: edited)
        guard case let .ready(result) = viewModel.state else {
            Issue.record("\(viewModel.state)")
            return
        }
        #expect(result.isIdentical)
    }

    @Test
    func anUnchangedPairIsNotComparedAgain() async {
        let compared = LockedBox(0)
        let viewModel = DiffViewModel { old, new in
            compared.mutate { $0 += 1 }
            return DiffViewModel.compare(old, new)
        }
        let base = flow(1, body: "a"), current = flow(2, body: "b")
        await viewModel.update(base: base, current: current)
        await viewModel.update(base: base, current: current)
        #expect(compared.value == 1)
    }

    @Test
    func aResultThatArrivesAfterANewerRequestIsDropped() async {
        let gate = SleepGate()
        let viewModel = DiffViewModel { old, new in
            try? await gate.sleep(.zero)
            return DiffViewModel.compare(old, new)
        }
        let base = flow(1, body: "same\nold")
        let first = flow(2, body: "same\nfirst"), second = flow(3, body: "same\nsecond\nmore")
        let firstUpdate = Task { await viewModel.update(base: base, current: first) }
        #expect(await eventually { gate.waitingCount == 1 })
        let secondUpdate = Task { await viewModel.update(base: base, current: second) }
        #expect(await eventually { gate.waitingCount == 2 })

        gate.releaseOldest()
        await firstUpdate.value
        #expect(viewModel.state == .computing, "the first result is stale")

        gate.releaseAll()
        await secondUpdate.value
        #expect(viewModel.state == .ready(DiffViewModel.compare("same\nold", "same\nsecond\nmore")))
    }

    @Test
    func aFlowWithoutAResponseHasNoStatusLineInItsHeaders() {
        let text = DiffViewModel.text(.fixture(sequence: 1, response: nil), .headers)
        #expect(!text.contains("HTTP"))
        #expect(DiffViewModel.text(flow(1, body: ""), .headers).contains("HTTP 200"))
    }

    @Test(arguments: [
        ("POST", "api.example.com", "/v1/users"),
        ("GET", "other.example.com", "/v1/users"),
    ])
    func aDifferentMethodOrHostIsNotTheSameEndpoint(method: String, host: String, path: String) {
        let earlier = Flow.fixture(sequence: 1, request: .fixture(method: method, host: host, path: path))
        let later = Flow.fixture(sequence: 2, request: .fixture(path: path))
        #expect(DiffViewModel.suggestedBase(for: later, in: [earlier, later]) == nil)
    }
}
