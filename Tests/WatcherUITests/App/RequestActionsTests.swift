import AppKit
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// What the request actions do to the store, the clipboard, the windows and the notice shown.
@MainActor
@Suite(.tags(.unit))
struct RequestActionsTests {
    private let store = FlowStore()
    private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }
    private let clipboard = ClipboardSpy()
    private let workspace = WorkspaceOpenerSpy()
    private let files = FileAccessFake()
    private let runner = ProxyRunnerStub()
    private let paths = SupportPaths(directory: URL(fileURLWithPath: "/fake-home/.watcher"))
    private let list: FlowListViewModel
    private let router: WindowRouter
    private let settings: SettingsEditor
    private let proxy: ProxyController

    init() {
        list = FlowListViewModel(store: store, sleep: sleepUntilCancelled)
        router = WindowRouter(notices: notices) {}
        settings = SettingsEditor(
            initial: WatcherSettings(), sleep: sleepUntilCancelled, notices: notices, persist: { _ in }, apply: { _ in }
        )
        let settings = settings
        proxy = ProxyController(runner: runner, systemProxy: SystemProxySpy(), notices: notices) { settings.value }
    }

    private func actions(sender: RequestSenderSpy = RequestSenderSpy()) -> RequestActions {
        RequestActions(
            services: .init(
                sender: sender, clipboard: clipboard, workspace: workspace, paths: paths, files: files.access
            ),
            store: store, settings: settings, notices: notices, router: router, list: list, proxy: proxy
        )
    }

    private func load(_ flows: [Flow]) {
        store.load(flows)
        list.syncFromStore()
    }

    private func startProxy() async {
        proxy.toggleRunning()
        _ = await eventually { proxy.isRunning && !proxy.isSwitchingProxy }
    }

    @Test
    func starringAMixedSelectionStarsEveryRequest() {
        let starred = Flow.fixture(sequence: 1, status: 200, starred: true)
        let plain = Flow.fixture(sequence: 2, status: 200)
        load([starred, plain])
        actions().toggleStar([starred.id, plain.id])
        #expect(!store.all.contains { !$0.isStarred })
        #expect(notices.notice?.message == "Starred")
    }

    @Test
    func starringAnAllStarredSelectionRemovesTheStars() {
        let flows = [1, 2].map { Flow.fixture(sequence: $0, status: 200, starred: true) }
        load(flows)
        actions().toggleStar(Set(flows.map(\.id)))
        #expect(store.all.allSatisfy { !$0.isStarred })
        #expect(notices.notice?.message == "Star removed")
    }

    @Test
    func commentAndDeleteReachTheStore() {
        let flow = Flow.fixture(sequence: 1, status: 200)
        load([flow])
        let actions = actions()
        actions.setComment("look", for: flow.id)
        #expect(store.all.first?.comment == "look")
        actions.delete([flow.id])
        #expect(store.all.isEmpty)
    }

    @Test
    func clearOffersUndoThatBringsTheRequestsBack() {
        let kept = ["/a", "/b"].map { store.begin(.fixture(host: "x.test", path: $0)) }
        actions().clear()
        #expect(store.all.isEmpty)
        #expect(notices.notice?.message == "Cleared 2 requests")
        let undo = notices.notice?.action
        #expect(undo?.title == "Undo")
        undo?.perform()
        #expect(store.all.map(\.id) == kept.map(\.id))
        #expect(notices.notice?.action == nil, "the follow-up notice cannot undo again")
        undo?.perform()
        #expect(store.all.count == 2, "a second tap on a stale Undo adds nothing")
    }

    @Test
    func clearingOneRequestSaysSoInTheSingular() {
        _ = store.begin(.fixture())
        actions().clear()
        #expect(notices.notice?.message == "Cleared 1 request")
    }

    @Test
    func clearingAnEmptySessionOffersNoUndo() {
        actions().clear()
        #expect(notices.notice?.message == "Session cleared")
        #expect(notices.notice?.action == nil)
    }

    @Test
    func sendingWhileStoppedAsksToStartTheProxy() {
        let sender = RequestSenderSpy()
        actions(sender: sender).send(.fixture())
        #expect(notices.notice?.kind == .error)
        #expect(notices.notice?.message == "Start the proxy to send requests.")
        #expect(sender.sent.isEmpty)
    }

    @Test(arguments: [(200, Notice.Kind.success), (399, .success), (400, .error), (503, .error)])
    func sendingSaysHowTheServerAnswered(status: Int, kind: Notice.Kind) async {
        await startProxy()
        actions(sender: RequestSenderSpy(status: status)).send(.fixture(host: "x.test"))
        #expect(await eventually { notices.notice?.message == "GET x.test → \(status)" })
        #expect(notices.notice?.kind == kind)
    }

    @Test(arguments: [true, false])
    func repeatingDropsCacheValidatorsOnlyWhenAsked(noCaching: Bool) async {
        await startProxy()
        settings.noCachingOnRepeat = noCaching
        let sender = RequestSenderSpy()
        let request = RequestRecord.fixture(headers: [Header("If-None-Match", "\"v1\"")])
        actions(sender: sender).repeatRequest(request)
        #expect(await eventually { sender.sent.count == 1 })
        #expect(sender.sent.first?.headers.value(for: "if-none-match") == (noCaching ? nil : "\"v1\""))
    }

    @Test
    func performReturnsTheAnswer() async {
        let response = await actions(sender: RequestSenderSpy(status: 201)).perform(.fixture(), followRedirects: true)
        #expect(response.status == 201)
    }

    @Test
    func aFailedWebSocketSessionIsReported() async {
        struct Refused: Error {}
        let sender = RequestSenderSpy(webSocketFailure: Refused())
        actions(sender: sender).composeWebSocket(url: URL(fileURLWithPath: "/ws"), headers: [], messages: ["hi"])
        #expect(await eventually { notices.notice?.kind == .error })
        #expect(sender.webSocketMessages == [["hi"]])
    }

    @Test
    func copyPutsTheTextOnTheClipboardAndConfirms() {
        actions().copy("curl https://x.test", "Copied as cURL")
        #expect(clipboard.text == "curl https://x.test")
        #expect(notices.notice?.kind == .success)
        #expect(notices.notice?.message == "Copied as cURL")
    }

    @Test
    func copyingAnImagePutsItOnTheClipboard() {
        actions().copy(image: NSImage(size: NSSize(width: 1, height: 1)))
        #expect(clipboard.images.count == 1)
        #expect(notices.notice?.message == "Image copied")
    }

    @Test(arguments: [nil, "", "hello world"])
    func composingFromAClipboardWithoutCurlIsRefused(text: String?) {
        if let text {
            clipboard.setString(text)
        }
        actions().composeFromClipboardCurl()
        #expect(router.sheet == nil)
        #expect(notices.notice?.message == "Copy a curl command first, then choose New Request from cURL.")
    }

    @Test
    func composingFromABrokenCurlReportsWhy() {
        clipboard.setString("curl 'https://x.test")
        actions().composeFromClipboardCurl()
        #expect(router.sheet == nil)
        #expect(notices.notice?.message.hasPrefix("Cannot read the cURL command") == true)
    }

    @Test
    func composingFromAValidCurlOpensCompose() {
        router.composeSource = .fixture()
        clipboard.setString("curl -X POST https://x.test/v1")
        actions().composeFromClipboardCurl()
        #expect(router.sheet == .compose)
        #expect(router.composeDraft?.method == "POST")
        #expect(router.composeDraft?.host == "x.test")
        #expect(router.composeSource == nil, "a pasted command has no captured original")
    }

    @Test
    func codeAddsTheProxyOnlyWhenAsked() {
        let request = RequestRecord.fixture(host: "x.test", path: "/a")
        settings.includeProxyInCURL = false
        #expect(!actions().code(for: request).contains(" -x "))
        settings.includeProxyInCURL = true
        #expect(actions().code(for: request).contains("http://127.0.0.1:\(settings.port)"))
        #expect(actions().code(for: request).contains("/fake-home/.watcher/watcher-ca.pem"))
    }

    @Test
    func editAndRepeatThenCompareWithTheOriginal() {
        let captured = RequestRecord.fixture(method: "POST", path: "/v1/items?x=1", body: Data(#"{"name":"A"}"#.utf8))
        let original = Flow.fixture(sequence: 1, request: captured, response: nil, state: .completed)
        let other = Flow.fixture(sequence: 2, request: .fixture(path: "/other"), response: nil, state: .completed)
        let resent = Flow.fixture(sequence: 3, request: captured, response: nil, state: .completed)
        [original, other, resent].forEach { list.enqueue(.added($0)) }
        list.flushEvents()
        let actions = actions()
        actions.editAndRepeat(original)
        #expect(router.sheet == .compose)
        #expect(router.composeSource?.id == original.id)

        actions.compareWithOriginal(original, sent: captured)
        #expect(router.diffBase?.id == original.id)
        #expect(list.selection == resent.id)
        #expect(router.sheet == nil)
    }

    @Test
    func comparingWithoutAResentRequestKeepsTheSelection() {
        let original = Flow.fixture(sequence: 1, status: 200)
        load([original])
        list.selection = original.id
        actions().compareWithOriginal(original, sent: .fixture(path: "/never-sent"))
        #expect(list.selection == original.id)
        #expect(router.diffBase?.id == original.id)
    }

    @Test
    func mockingAResponseWritesItsFileAddsARuleAndOpensIt() throws {
        let flow = Flow.fixture(
            request: .fixture(host: "api.example.com", path: "/v1/users?page=2"),
            response: .fixture(headers: [Header("Content-Type", "application/json")], body: Data("[]".utf8))
        )
        actions().mockResponse(flow)
        let opened = try #require(workspace.opened.first)
        #expect(opened.path.hasPrefix("/fake-home/.watcher/mocks/"))
        #expect(files.contents(of: opened.path) == Data("[]".utf8))
        #expect(settings.mapLocal.isEnabled)
        #expect(settings.mapLocal.rules.count == 1)
        #expect(notices.notice?.message.hasPrefix("Mock created: GET /v1/users now answers from") == true)
    }

    @Test
    func mockingWithoutAResponseIsReported() {
        actions().mockResponse(.fixture(response: nil))
        #expect(notices.notice?.kind == .error)
        #expect(workspace.opened.isEmpty)
        #expect(settings.mapLocal.rules.isEmpty)
    }

    @Test
    func revealingTheCertificateShowsItInFinder() {
        actions().revealCertificate()
        #expect(workspace.revealed == [[URL(fileURLWithPath: "/fake-home/.watcher/watcher-ca.pem")]])
    }
}
