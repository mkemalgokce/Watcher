import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// Picking files for the editors: a multipart upload part read through the file system, and a Map Local path.
@MainActor
@Suite(.tags(.unit))
struct FilePickerTests {
    private let files = FileAccessFake()

    private func picker(_ panels: FilePanelsStub) -> FilePicker {
        FilePicker(panels: panels, files: files.access)
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
        let part = await picker(FilePanelsStub(open: url)).choosePart()
        #expect(part == KeyValue.FilePart(filename: name, contentType: type, data: Data([1, 2, 3])))
    }

    @Test
    func aCancelledFilePartPanelChoosesNothing() async {
        let panels = FilePanelsStub()
        #expect(await picker(panels).choosePart() == nil)
        #expect(panels.openRequests == [false], "a file, not a folder, was asked for")
    }

    @Test
    func keepingTheCurrentFilePartSurvivesACancelledOrUnreadablePick() async throws {
        let current = KeyValue.FilePart(filename: "old.png", contentType: "image/png", data: Data([9]))
        #expect(await picker(FilePanelsStub()).choosePart(keeping: current) == current)
        let missing = URL(fileURLWithPath: "/fake-home/in/missing.png")
        #expect(await picker(FilePanelsStub(open: missing)).choosePart(keeping: current) == current)
        let url = URL(fileURLWithPath: "/fake-home/in/new.png")
        try files.write(Data([1]), to: url.path)
        let chosen = await picker(FilePanelsStub(open: url)).choosePart(keeping: current)
        #expect(chosen?.filename == "new.png")
        #expect(await picker(FilePanelsStub()).choosePart(keeping: nil) == nil)
    }

    @Test
    func anUnreadableFilePartChoosesNothing() async {
        let missing = URL(fileURLWithPath: "/fake-home/in/missing.png")
        #expect(await picker(FilePanelsStub(open: missing)).choosePart() == nil)
    }

    @Test(arguments: [
        (false, MapLocalRule.Source.file("/fake-home/mocks/users.json")),
        (true, .directory("/fake-home/mocks/users.json")),
    ])
    func aMapLocalSourceKeepsItsKindAndTakesThePickedPath(directory: Bool, expected: MapLocalRule.Source) {
        let panels = FilePanelsStub(open: URL(fileURLWithPath: "/fake-home/mocks/users.json"))
        #expect(picker(panels).chooseSource(directory: directory) == expected)
        #expect(panels.openRequests == [directory])
    }

    @Test
    func aCancelledMapLocalPanelChoosesNothing() {
        #expect(picker(FilePanelsStub()).chooseSource(directory: true) == nil)
    }
}
