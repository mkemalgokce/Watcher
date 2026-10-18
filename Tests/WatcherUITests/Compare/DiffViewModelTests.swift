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
}
