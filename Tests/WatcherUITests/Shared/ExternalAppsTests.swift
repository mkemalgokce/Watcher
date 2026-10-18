import AppKit
import Testing
import UniformTypeIdentifiers
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(.tags(.unit))
struct ExternalAppsTests {
    private let notices = NoticeCenter.silent()
    private let file = URL(fileURLWithPath: "/tmp/Watcher Open/1/body.json")
    private let preview = URL(fileURLWithPath: "/System/Applications/Preview.app")
    private let editor = URL(fileURLWithPath: "/Applications/Editor.app")

    private func makeApps(_ workspace: WorkspaceOpenerSpy? = nil) -> ExternalApps {
        ExternalApps(workspace: workspace ?? WorkspaceOpenerSpy(), notices: notices, files: FileAccessFake().access)
    }

    @Test
    func theDefaultAppComesFirstAndOnlyOnce() {
        let workspace = WorkspaceOpenerSpy(applications: [editor, preview], defaultApplication: preview)
        let apps = makeApps(workspace)
        #expect(apps.applications(contentType: "application/json", data: Data("{}".utf8)) == [preview, editor])
        #expect(workspace.askedTypes == [.json])
    }

    @Test
    func atMostTwelveOtherAppsAreOffered() {
        let many = (1 ... 20).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
        let workspace = WorkspaceOpenerSpy(applications: many, defaultApplication: preview)
        let apps = makeApps(workspace)
        let offered = apps.applications(contentType: "application/json", data: Data())
        #expect(offered.count == 13)
        #expect(offered.first == preview)
    }

    @Test
    func withoutADefaultAppTheOthersAreOffered() {
        let workspace = WorkspaceOpenerSpy(applications: [editor])
        let apps = makeApps(workspace)
        #expect(apps.applications(contentType: "text/plain", data: Data()) == [editor])
    }

    @Test
    func openingInTheDefaultAppSaysNothingWhenItWorks() async {
        let workspace = WorkspaceOpenerSpy()
        await makeApps(workspace).open(file, with: nil)
        #expect(workspace.opened == [file])
        #expect(notices.notice == nil)
    }

    @Test
    func aFileNoAppOpensSaysToPickOne() async {
        let workspace = WorkspaceOpenerSpy()
        workspace.opensFiles = false
        await makeApps(workspace).open(file, with: nil)
        #expect(notices.notice?.message == "No app opens json files. Use Open With to pick one.")
        #expect(notices.notice?.kind == .error)
    }

    @Test
    func openingInAChosenAppUsesThatApp() async {
        let workspace = WorkspaceOpenerSpy()
        await makeApps(workspace).open(file, with: editor)
        #expect(workspace.openedWith.map(\.file) == [file])
        #expect(workspace.openedWith.map(\.app) == [editor])
        #expect(workspace.opened.isEmpty)
        #expect(notices.notice == nil)
    }

    @Test
    func aChosenAppThatFailsIsNamedInTheNotice() async {
        let workspace = WorkspaceOpenerSpy()
        workspace.openWithFailure = CocoaError(.fileReadNoPermission)
        await makeApps(workspace).open(file, with: editor)
        let message = notices.notice?.message ?? ""
        #expect(message.hasPrefix("Cannot open with Editor: "))
        #expect(notices.notice?.kind == .error)
    }

    @Test
    func anAppIsNamedAsFinderNamesIt() {
        let apps = makeApps()
        #expect(apps.name(of: editor) == "Editor")
    }

    @Test
    func showingInFinderRevealsJustThatFile() {
        let workspace = WorkspaceOpenerSpy()
        makeApps(workspace).reveal(file)
        #expect(workspace.revealed == [[file]])
    }

    @Test
    func contentIsWrittenToItsOwnFolderUnderItsOwnName() throws {
        let files = FileAccessFake()
        let apps = ExternalApps(workspace: WorkspaceOpenerSpy(), notices: notices, files: files.access)
        let first = try apps.write(Data("{}".utf8), name: "users.json", contentType: nil)
        let second = try apps.write(Data("{}".utf8), name: "users.json", contentType: nil)
        #expect(first.lastPathComponent == "users.json")
        #expect(first.deletingLastPathComponent() != second.deletingLastPathComponent(), "no write replaces another")
        #expect(files.contents(of: first.path) == Data("{}".utf8))
        #expect(files.folders.contains(first.deletingLastPathComponent().path))
    }

    @Test(arguments: [
        ("", "application/json", "body.json"),
        ("/", "text/plain", "body.txt"),
        ("image", "image/png", "image.png"),
        ("report.pdf", nil, "report.pdf"),
        ("data", nil, "data.txt"),
    ])
    func theNameFallsBackToBodyAndTheExtensionToTheContentType(name: String, type: String?, expected: String) throws {
        let apps = makeApps()
        #expect(try apps.write(Data("x".utf8), name: name, contentType: type).lastPathComponent == expected)
    }

    @Test
    func aWriteThatFailsThrows() {
        struct Disk: Error {}
        var access = FileAccessFake().access
        access.writeAtomically = { _, _ in throw Disk() }
        let apps = ExternalApps(workspace: WorkspaceOpenerSpy(), notices: notices, files: access)
        #expect(throws: Disk.self) { try apps.write(Data("x".utf8), name: "a.txt", contentType: nil) }
    }

    @Test
    func discardingAWrittenFileRemovesItAndItsFolder() throws {
        let files = FileAccessFake()
        let apps = ExternalApps(workspace: WorkspaceOpenerSpy(), notices: notices, files: files.access)
        let url = try apps.write(Data("x".utf8), name: "a.txt", contentType: nil)
        apps.discard(url)
        #expect(files.contents(of: url.path) == nil)
        #expect(!files.folders.contains(url.deletingLastPathComponent().path))
    }
}
