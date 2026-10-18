import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

private struct NotInstalled: Error {}

extension SessionFilesViewModelTests {
    /// What the exports write, and the edge cases of saving and opening around them.
    @MainActor
    struct Exports {
        private static let target = URL(fileURLWithPath: "/fake-home/out/export")
        private let files = FileAccessFake()
        private let store = FlowStore()
        private let notices = NoticeCenter.silent()
        private let flows = [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 404)]

        private func viewModel(
            _ panels: FilePanelsStub, load: [Flow]? = nil, commands: CommandRunnerSpy = CommandRunnerSpy()
        ) -> SessionFilesViewModel {
            store.load(load ?? flows)
            return SessionFilesViewModel(
                panels: panels, files: files.access, commands: commands.runner, store: store, notices: notices
            )
        }

        @Test
        func theHARExportReadsBackAsTheSameRequests() async throws {
            let url = Self.target.appendingPathExtension("har")
            let model = viewModel(FilePanelsStub(save: url))
            model.exportHAR()
            #expect(await eventually { model.busyMessage == nil })
            let written = try #require(files.contents(of: url.path))
            let read = try HAR.flows(from: written)
            #expect(read.map(\.request.url) == flows.map(\.request.url))
            #expect(read.compactMap(\.response?.status) == [200, 404])
        }

        @Test
        func theCSVExportHasAHeaderAndOneRowPerRequest() async throws {
            let url = Self.target.appendingPathExtension("csv")
            let model = viewModel(FilePanelsStub(save: url))
            model.exportCSV()
            #expect(await eventually { model.busyMessage == nil })
            let text = try String(bytes: #require(files.contents(of: url.path)), encoding: .utf8) ?? ""
            let lines = text.components(separatedBy: "\r\n").filter { !$0.isEmpty }
            #expect(lines.count == 3)
            guard lines.count == 3 else { return }
            #expect(lines[0].hasPrefix("#,Method,URL,Status"))
            #expect(lines[1].contains("200") && lines[2].contains("404"))
        }

        @Test
        func anEmptySessionIsExportedAsZeroRequests() async {
            let url = Self.target.appendingPathExtension("watcher")
            let model = viewModel(FilePanelsStub(save: url), load: [])
            model.saveSession()
            #expect(await eventually { model.busyMessage == nil })
            #expect(notices.notice?.message == "Saved 0 requests to export.watcher")
            #expect(files.contents(of: url.path) != nil)
        }

        @Test
        func aCancelledDataSaveWritesNothing() async {
            let panels = FilePanelsStub()
            let model = viewModel(panels)
            model.saveData(Data("x".utf8), suggestedName: "body.txt")
            await settle(0.05)
            #expect(files.paths.isEmpty)
            #expect(notices.notice == nil)
            #expect(panels.saveRequests.map(\.suggestedName) == ["body.txt"])
        }

        @Test
        func aDataSaveDoesNotWaitForOrShowTheSessionProgress() async {
            let url = Self.target.appendingPathExtension("txt")
            let model = viewModel(FilePanelsStub(save: url))
            model.saveData(Data("x".utf8), suggestedName: "body.txt")
            #expect(model.busyMessage == nil)
            #expect(await eventually { files.contents(of: url.path) != nil })
        }

        @Test
        func aFileOfAnUnknownKindIsReadAsASessionAndFailsAsOneWhenItIsNot() async {
            let url = URL(fileURLWithPath: "/fake-home/in/notes.txt")
            files.write(Data("hello".utf8), to: url.path)
            let model = viewModel(FilePanelsStub())
            await model.importFile(at: url)
            #expect(notices.notice?.kind == .error)
            #expect(notices.notice?.message.hasPrefix("Cannot open notes.txt") == true)
            #expect(store.all.count == 2, "a file that cannot be read leaves the session alone")
        }

        @Test
        func aCharlesConversionThatFailsIsReported() async {
            let url = URL(fileURLWithPath: "/fake-home/in/session.chls")
            let commands = CommandRunnerSpy(failure: NotInstalled())
            let fake = FileAccessFake(executables: [CharlesConverter.defaultExecutable.path])
            let model = SessionFilesViewModel(
                panels: FilePanelsStub(), files: fake.access, commands: commands.runner, store: store, notices: notices
            )
            await model.importFile(at: url)
            #expect(notices.notice?.kind == .error)
            #expect(notices.notice?.message.hasPrefix("Cannot open session.chls") == true)
            #expect(model.busyMessage == nil)
        }

        @Test
        func anEncoderThatFailsClearsTheProgressAndReportsTheFile() async {
            let url = Self.target.appendingPathExtension("watcher")
            files.fail(.writeAtomically)
            let model = viewModel(FilePanelsStub(save: url))
            model.saveSession()
            #expect(await eventually { model.busyMessage == nil })
            #expect(notices.notice?.message.hasPrefix("Cannot save export.watcher") == true)
        }
    }
}
