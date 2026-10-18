import Foundation
import Testing
import UniformTypeIdentifiers
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Saving, exporting and opening session files: the panel asked, what is written or loaded, and the feedback shown.
@MainActor
@Suite(.tags(.unit))
struct SessionFilesViewModelTests {
    private static let saved = URL(fileURLWithPath: "/fake-home/out/session.watcher")
    private let files = FileAccessFake()
    private let store = FlowStore()
    private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }
    private let flows = [Flow.fixture(sequence: 1, status: 200), .fixture(sequence: 2, status: 404)]

    private func viewModel(
        _ panels: FilePanelsStub,
        commands: CommandRunnerSpy = CommandRunnerSpy()
    ) -> SessionFilesViewModel {
        store.load(flows)
        return SessionFilesViewModel(
            panels: panels,
            files: files.access,
            commands: commands.runner,
            store: store,
            notices: notices
        )
    }

    @Test(arguments: [
        ("session.har", UTType.json),
        ("session.csv", .commaSeparatedText),
        ("session.watcher", .json),
    ])
    func eachExportOffersItsNameAndType(name: String, type: UTType) {
        let panels = FilePanelsStub()
        let model = viewModel(panels)
        switch name {
        case "session.har": model.exportHAR()
        case "session.csv": model.exportCSV()
        default: model.saveSession()
        }
        #expect(panels.saveRequests == [.init(suggestedName: name, contentTypes: [type])])
        #expect(model.busyMessage == nil, "a cancelled panel starts nothing")
        #expect(files.paths.isEmpty)
    }

    @Test
    func savingASessionWritesEveryRequest() async throws {
        let model = viewModel(FilePanelsStub(save: Self.saved))
        model.saveSession()
        #expect(model.busyMessage == "Saving session.watcher…")
        #expect(await eventually { model.busyMessage == nil })
        let written = try #require(files.contents(of: Self.saved.path))
        #expect(try SessionFile.decode(written).map(\.id) == flows.map(\.id))
        #expect(notices.notice?.message == "Saved 2 requests to session.watcher")
        #expect(notices.notice?.kind == .success)
    }

    @Test
    func aFailedWriteIsReported() async {
        files.fail(.writeAtomically)
        let model = viewModel(FilePanelsStub(save: Self.saved))
        model.exportCSV()
        #expect(await eventually { model.busyMessage == nil })
        #expect(notices.notice?.kind == .error)
        #expect(notices.notice?.message.hasPrefix("Cannot save session.watcher") == true)
    }

    @Test
    func openingFromThePanelLoadsTheFile() async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/old.watcher")
        try files.write(SessionFile.encode(flows), to: url.path)
        let panels = FilePanelsStub(open: url)
        let model = viewModel(panels)
        model.importFile()
        #expect(panels.openRequests == [false])
        #expect(await eventually { notices.notice?.message == "Opened 2 requests from old.watcher" })
        #expect(store.all.count == 2)
    }

    @Test
    func aCancelledOpenPanelDoesNothing() {
        let model = viewModel(FilePanelsStub())
        model.importFile()
        #expect(model.busyMessage == nil)
        #expect(notices.notice == nil)
    }

    @Test(arguments: ["session.har", "session.HAR"])
    func harFilesAreReadAsHAR(name: String) async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/\(name)")
        try files.write(HAR.export(flows), to: url.path)
        let model = viewModel(FilePanelsStub())
        store.load([])
        await model.importFile(at: url)
        #expect(store.all.count == 2)
    }

    @Test
    func charlesJSONSessionsAreReadAsCharles() async {
        let url = URL(fileURLWithPath: "/fake-home/in/session.chlsj")
        let session = #"[{"scheme":"https","host":"x.test","path":"/a","method":"GET","status":"COMPLETE"}]"#
        files.write(Data(session.utf8), to: url.path)
        await viewModel(FilePanelsStub()).importFile(at: url)
        #expect(store.all.map(\.request.host) == ["x.test"])
    }

    @Test(arguments: ["chls", "chlz"])
    func binaryCharlesSessionsAreConvertedByCharles(ext: String) async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/session.\(ext)")
        let charles = CharlesConverter.defaultExecutable.path
        let fake = FileAccessFake(executables: [charles])
        let har = try HAR.export(flows)
        let commands = CommandRunnerSpy { fake.write(har, to: $0.arguments[2]) }
        let model = SessionFilesViewModel(
            panels: FilePanelsStub(), files: fake.access, commands: commands.runner,
            store: store, notices: notices
        )
        await model.importFile(at: url)
        #expect(commands.commands.map(\.executable.path) == [charles])
        #expect(store.all.count == 2)
    }

    @Test
    func aBrokenFileShowsAnError() async {
        let url = URL(fileURLWithPath: "/fake-home/in/broken.har")
        files.write(Data("not json".utf8), to: url.path)
        let model = viewModel(FilePanelsStub())
        await model.importFile(at: url)
        #expect(notices.notice?.kind == .error)
        #expect(notices.notice?.message.hasPrefix("Cannot open broken.har") == true)
        #expect(model.busyMessage == nil)
    }

    @Test
    func anEmptySessionSaysSo() async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/empty.watcher")
        try files.write(SessionFile.encode([]), to: url.path)
        await viewModel(FilePanelsStub()).importFile(at: url)
        #expect(notices.notice?.kind == .info)
        #expect(notices.notice?.message == "empty.watcher has no requests")
    }

    @Test
    func openingWhileBusyIsRefused() async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/old.watcher")
        try files.write(SessionFile.encode(flows), to: url.path)
        let model = viewModel(FilePanelsStub(save: Self.saved))
        model.saveSession()
        await model.importFile(at: url)
        #expect(notices.notice?.message == "Wait for the current file to finish.")
        #expect(await eventually { model.busyMessage == nil })
    }

    @Test
    func savingWhileBusyIsRefusedBeforeThePanelOpens() async {
        let panels = FilePanelsStub(save: Self.saved)
        let model = viewModel(panels)
        model.saveSession()
        model.exportHAR()
        #expect(panels.saveRequests.map(\.suggestedName) == ["session.watcher"])
        #expect(notices.notice?.message == "Wait for the current file to finish.")
        #expect(model.busyMessage == "Saving session.watcher…", "the first save keeps its progress message")
        #expect(await eventually { model.busyMessage == nil })
    }

    @Test
    func savingDataWritesItAndSaysHowBig() async {
        let target = URL(fileURLWithPath: "/fake-home/out/users.json")
        let panels = FilePanelsStub(save: target)
        let model = viewModel(panels)
        model.saveData(Data("{}".utf8), suggestedName: "users.json")
        #expect(panels.saveRequests == [.init(suggestedName: "users.json", contentTypes: [])])
        #expect(await eventually { files.contents(of: target.path) == Data("{}".utf8) })
        #expect(await eventually { notices.notice?.message == "Saved users.json (2 B)" })
    }

    @Test
    func savingABodyOffersTheSuggestedName() async {
        let target = URL(fileURLWithPath: "/fake-home/out/users.json")
        let panels = FilePanelsStub(save: target)
        let flow = Flow.fixture(
            request: .fixture(path: "/v1/users"),
            response: .fixture(headers: [Header("Content-Type", "application/json")], body: Data("[]".utf8))
        )
        viewModel(panels).saveBody(of: flow, side: .response)
        #expect(panels.saveRequests.map(\.suggestedName) == ["users.json"])
        #expect(await eventually { files.contents(of: target.path) == Data("[]".utf8) })
    }

    @Test
    func aFailedDataSaveIsReported() async {
        files.fail(.writeAtomically)
        let model = viewModel(FilePanelsStub(save: URL(fileURLWithPath: "/fake-home/out/a.bin")))
        model.saveData(Data([1]), suggestedName: "a.bin")
        #expect(await eventually { notices.notice?.kind == .error })
        #expect(notices.notice?.message.hasPrefix("Cannot save a.bin") == true)
    }

    @Test(arguments: [
        ("photo.png", "image/png"),
        ("notes.TXT", "text/plain"),
        ("blob.unknownext", "application/octet-stream"),
        ("no-extension", "application/octet-stream"),
    ])
    func aChosenFilePartIsReadThroughTheFileSystem(name: String, type: String) async throws {
        let url = URL(fileURLWithPath: "/fake-home/in/\(name)")
        try files.write(Data([1, 2, 3]), to: url.path)
        let part = await viewModel(FilePanelsStub(open: url)).chooseFilePart()
        #expect(part == KeyValue.FilePart(filename: name, contentType: type, data: Data([1, 2, 3])))
    }

    @Test
    func aCancelledFilePartPanelChoosesNothing() async {
        let panels = FilePanelsStub()
        #expect(await viewModel(panels).chooseFilePart() == nil)
        #expect(panels.openRequests == [false], "a file, not a folder, was asked for")
    }

    @Test
    func anUnreadableFilePartChoosesNothing() async {
        let missing = URL(fileURLWithPath: "/fake-home/in/missing.png")
        #expect(await viewModel(FilePanelsStub(open: missing)).chooseFilePart() == nil)
    }
}
