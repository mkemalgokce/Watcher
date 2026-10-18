import Foundation
import SnapshotTesting
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// Compare: the states the window shows and the rows of a change, inline and side by side.
    @MainActor
    struct Compare {
        private func flow(_ sequence: Int, _ body: String) -> Flow {
            .fixture(
                sequence: sequence,
                response: .fixture(headers: [Header("Content-Type", "text/plain")], body: Data(body.utf8))
            )
        }

        private func describe(_ result: DiffViewModel.Result) -> [String] {
            let inline = result.lines.map { "\($0.kind) \($0.text)" }
            let rows = result.rows.map { "\($0.left?.text ?? "") | \($0.right?.text ?? "")" }
            return ["+\(result.added) -\(result.removed)"] + inline + ["side by side:"] + rows
        }

        @Test
        func everyStateOfTheComparison() async {
            let viewModel = DiffViewModel()
            let base = flow(1, "keep\nold\nend"), changed = flow(2, "keep\nnew\nend")
            var lines: [String] = []
            for (base, current) in [(nil, base), (base, base), (base, flow(3, "keep\nold\nend")), (base, changed)] {
                await viewModel.update(base: base, current: current)
                switch viewModel.state {
                case let .ready(result): lines += ["ready"] + describe(result)
                case let state: lines.append("\(state)")
                }
            }
            lines.append("suggested: \(DiffViewModel.suggestedBase(for: changed, in: [base, changed])?.sequence ?? 0)")
            assertSnapshot(of: lines.joined(separator: "\n"), as: .lines)
        }
    }
}
