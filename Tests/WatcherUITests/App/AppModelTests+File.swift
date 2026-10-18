import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension AppModelTests {
    /// Saving and opening files from the window: progress, success, empty and error states, and the names offered.
    @MainActor
    struct File {
        @Test
        func saveAndOpenSessionReportProgressAndResult() async throws {
            let model = AppModel(listening: false)
            let directory = try TemporaryDirectory()
            let url = directory.appending("watcher.watcher")

            let flows = [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 200)]
            let saving = Task { await model.write(flows, to: url) { try SessionFile.encode($0) } }
            await Task.yield()
            #expect(model.busyMessage != nil, "saving shows a busy state right away")
            await saving.value
            #expect(model.busyMessage == nil)
            #expect(model.notice?.kind == .success)

            await model.importFile(at: url)
            #expect(model.busyMessage == nil)
            #expect(model.notice?.kind == .success)
            #expect(model.notice?.message == "Opened 2 requests from \(url.lastPathComponent)")
            model.syncFromStore()
            #expect(model.flows.count == 2)
        }

        @Test
        func openingABrokenFileShowsAnError() async throws {
            let model = AppModel(listening: false)
            let directory = try TemporaryDirectory()
            let url = directory.appending("broken.har")
            try Data("not json".utf8).write(to: url)
            await model.importFile(at: url)
            #expect(model.notice?.kind == .error)
            #expect(model.busyMessage == nil)
        }

        @Test
        func openingAnEmptySessionSaysSo() async throws {
            let model = AppModel(listening: false)
            let directory = try TemporaryDirectory()
            let url = directory.appending("empty.watcher")
            try SessionFile.encode([]).write(to: url)
            await model.importFile(at: url)
            #expect(model.notice?.kind == .info)
            #expect(model.notice?.message.contains("no requests") == true)
        }

        @Test
        func suggestedFileNames() {
            let model = AppModel(listening: false)
            let json = [Header("Content-Type", "application/json; charset=utf-8")]
            var flow = Flow.fixture(
                request: .fixture(host: "h", path: "/v1/users?page=2"),
                response: .fixture(headers: json, body: Data("{}".utf8))
            )
            #expect(model.suggestedFileName(for: flow, side: .response) == "users.json")
            flow.request.path = "/files/report.pdf"
            #expect(
                model.suggestedFileName(for: flow, side: .response) == "report.pdf",
                "an extension in the URL is kept"
            )
            flow.request.path = "/"
            #expect(model.suggestedFileName(for: flow, side: .response) == "response.json")
            flow.response?.headers = []
            #expect(model.suggestedFileName(for: flow, side: .response) == "response")
        }
    }
}
