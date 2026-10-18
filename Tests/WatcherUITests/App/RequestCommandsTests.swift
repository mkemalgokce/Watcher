import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// What each request action offers and does for one request, whichever place it is invoked from.
@MainActor
@Suite(.tags(.unit))
struct RequestCommandsTests {
    typealias Command = RequestCommands.Command

    private let clipboard = ClipboardSpy()
    private let panels = FilePanelsStub()

    private func commands(for flow: Flow?, ids: Set<Flow.ID>? = nil) throws -> (RequestCommands, AppModel) {
        let model = try AppModel(dependencies: .test(clipboard: clipboard, panels: panels))
        if let flow {
            model.engine.store.load([flow])
            model.list.syncFromStore()
        }
        return (model.requestCommands(for: flow, ids: ids), model)
    }

    private static let body = Data("x".utf8)
    private static let flows: [(String, Flow)] = [
        ("pending", .fixture(response: nil, state: .pending)),
        ("failed", .fixture(response: nil, state: .failed)),
        ("blocked", .fixture(response: nil, state: .blocked)),
        ("empty body", .fixture(response: .fixture(status: 200, body: Data()))),
        ("with body", .fixture(response: .fixture(status: 200, body: body))),
    ]

    @Test(arguments: flows)
    func everyActionNeedsARequestAndSomeNeedMore(name: String, flow: Flow) throws {
        let (commands, _) = try commands(for: flow)
        let hasResponse = flow.response != nil
        let hasResponseBody = !(flow.response?.body.isEmpty ?? true)
        #expect(commands.isEnabled(.repeatRequest), "\(name)")
        #expect(commands.isEnabled(.editAndRepeat), "\(name)")
        #expect(commands.isEnabled(.toggleStar), "\(name)")
        #expect(commands.isEnabled(.copyCURL), "\(name)")
        #expect(commands.isEnabled(.copyURL), "\(name)")
        #expect(commands.isEnabled(.copyRequestHeaders), "\(name)")
        #expect(commands.isEnabled(.setCompareBase), "\(name)")
        #expect(commands.isEnabled(.delete), "\(name)")
        #expect(commands.isEnabled(.mockResponse) == hasResponse, "\(name)")
        #expect(commands.isEnabled(.copyResponseHeaders) == hasResponse, "\(name)")
        #expect(commands.isEnabled(.saveResponseBody) == hasResponseBody, "\(name)")
        #expect(!commands.isEnabled(.saveRequestBody), "\(name): the fixture request has no body")
    }

    @Test(arguments: Command.allCases)
    func nothingIsOfferedWithoutARequest(command: Command) throws {
        let (commands, _) = try commands(for: nil)
        #expect(!commands.isEnabled(command))
    }

    @Test
    func aRequestBodyCanBeSaved() throws {
        let flow = Flow.fixture(request: .fixture(body: Self.body))
        let (commands, _) = try commands(for: flow)
        #expect(commands.isEnabled(.saveRequestBody))
    }

    @Test
    func theStarTitleFollowsTheStar() throws {
        #expect(try commands(for: .fixture(starred: true)).0.starTitle == "Remove Star")
        #expect(try commands(for: .fixture()).0.starTitle == "Star")
        #expect(try commands(for: nil).0.starTitle == "Star")
    }

    @Test
    func copyingPutsTheTextOnTheClipboardWithOneNoticePerKind() throws {
        let flow = Flow.fixture(request: .fixture(host: "a.test", path: "/x"))
        let (commands, model) = try commands(for: flow)
        commands.perform(.copyURL)
        #expect(clipboard.text == flow.request.url)
        #expect(model.notices.notice?.message == "URL copied")
        commands.perform(.copyCURL)
        #expect(clipboard.text?.hasPrefix("curl") == true)
        #expect(model.notices.notice?.message == "cURL copied")
    }

    @Test
    func starringFlipsTheStarOfEveryTargetedRequest() throws {
        let flow = Flow.fixture()
        let (commands, model) = try commands(for: flow, ids: [flow.id])
        commands.perform(.toggleStar)
        #expect(model.engine.store.all.first?.isStarred == true)
    }

    @Test
    func deletingRemovesTheTargetedRequests() throws {
        let flow = Flow.fixture()
        let (commands, model) = try commands(for: flow)
        commands.perform(.delete)
        #expect(model.engine.store.all.isEmpty)
    }

    @Test
    func setAsCompareBaseRemembersTheRequest() throws {
        let flow = Flow.fixture()
        let (commands, model) = try commands(for: flow)
        commands.perform(.setCompareBase)
        #expect(model.router.diffBase?.id == flow.id)
    }

    @Test
    func savingTheResponseBodyOffersItsFileName() throws {
        let flow = Flow.fixture(response: .fixture(status: 200, body: Self.body))
        let (commands, _) = try commands(for: flow)
        commands.perform(.saveResponseBody)
        #expect(panels.saveRequests.count == 1)
    }

    @Test(arguments: Command.allCases)
    func performingADisabledCommandDoesNothing(command: Command) throws {
        let (commands, model) = try commands(for: nil)
        commands.perform(command)
        #expect(clipboard.text == nil)
        #expect(model.notices.notice == nil)
        #expect(panels.saveRequests.isEmpty)
    }
}
