import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension RequestActionsTests {
    @MainActor
    @Suite(.tags(.unit))
    struct Previews {
        @Test
        func previewsComeFromTheEnginesPreviewers() async throws {
            let flow = Flow.fixture(sequence: 1, status: 200)
            let output = PreviewOutput(name: "Summary", text: "ok")
            let asked = LockedBox<[Flow.ID]>([])
            let model = try AppModel(dependencies: .test(previews: { flow in
                asked.mutate { $0.append(flow.id) }
                return [output]
            }))
            let shown = await model.actions.previews(for: flow)
            #expect(shown.map(\.name) == [output.name])
            #expect(shown.map(\.text) == [output.text])
            #expect(asked.value == [flow.id])
        }

        @Test
        func withoutPreviewersThereIsNothingToShow() async throws {
            let model = try AppModel(dependencies: .test())
            #expect(await model.actions.previews(for: .fixture(sequence: 1, status: 200)).isEmpty)
        }
    }
}
