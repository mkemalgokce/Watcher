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

    @Test
    func theDefaultAppComesFirstAndOnlyOnce() {
        let workspace = WorkspaceOpenerSpy(applications: [editor, preview], defaultApplication: preview)
        let apps = ExternalApps(workspace: workspace, notices: notices)
        #expect(apps.applications(contentType: "application/json", data: Data("{}".utf8)) == [preview, editor])
        #expect(workspace.askedTypes == [.json])
    }

    @Test
    func atMostTwelveOtherAppsAreOffered() {
        let many = (1 ... 20).map { URL(fileURLWithPath: "/Applications/App\($0).app") }
        let workspace = WorkspaceOpenerSpy(applications: many, defaultApplication: preview)
        let apps = ExternalApps(workspace: workspace, notices: notices)
        let offered = apps.applications(contentType: "application/json", data: Data())
        #expect(offered.count == 13)
        #expect(offered.first == preview)
    }

    @Test
    func withoutADefaultAppTheOthersAreOffered() {
        let workspace = WorkspaceOpenerSpy(applications: [editor])
        let apps = ExternalApps(workspace: workspace, notices: notices)
        #expect(apps.applications(contentType: "text/plain", data: Data()) == [editor])
    }

    @Test
    func openingInTheDefaultAppSaysNothingWhenItWorks() async {
        let workspace = WorkspaceOpenerSpy()
        await ExternalApps(workspace: workspace, notices: notices).open(file, with: nil)
        #expect(workspace.opened == [file])
        #expect(notices.notice == nil)
    }

    @Test
    func aFileNoAppOpensSaysToPickOne() async {
        let workspace = WorkspaceOpenerSpy()
        workspace.opensFiles = false
        await ExternalApps(workspace: workspace, notices: notices).open(file, with: nil)
        #expect(notices.notice?.message == "No app opens json files. Use Open With to pick one.")
        #expect(notices.notice?.kind == .error)
    }

    @Test
    func openingInAChosenAppUsesThatApp() async {
        let workspace = WorkspaceOpenerSpy()
        await ExternalApps(workspace: workspace, notices: notices).open(file, with: editor)
        #expect(workspace.openedWith.map(\.file) == [file])
        #expect(workspace.openedWith.map(\.app) == [editor])
        #expect(workspace.opened.isEmpty)
        #expect(notices.notice == nil)
    }

    @Test
    func aChosenAppThatFailsIsNamedInTheNotice() async {
        let workspace = WorkspaceOpenerSpy()
        workspace.openWithFailure = CocoaError(.fileReadNoPermission)
        await ExternalApps(workspace: workspace, notices: notices).open(file, with: editor)
        let message = notices.notice?.message ?? ""
        #expect(message.hasPrefix("Cannot open with Editor: "))
        #expect(notices.notice?.kind == .error)
    }

    @Test
    func anAppIsNamedAsFinderNamesIt() {
        let apps = ExternalApps(workspace: WorkspaceOpenerSpy(), notices: notices)
        #expect(apps.name(of: editor) == "Editor")
    }

    @Test
    func showingInFinderRevealsJustThatFile() {
        let workspace = WorkspaceOpenerSpy()
        ExternalApps(workspace: workspace, notices: notices).reveal(file)
        #expect(workspace.revealed == [[file]])
    }
}
