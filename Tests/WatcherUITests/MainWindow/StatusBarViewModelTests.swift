import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(.tags(.unit))
struct StatusBarViewModelTests {
    private let systemProxy = SystemProxySpy()

    private func model(lan: [String] = ["192.168.1.5"], clipboard: ClipboardSpy? = nil) throws -> AppModel {
        let probe = DevicesViewModel.DeviceProbe(
            simulators: { [] }, androidDevices: { [] }, isMacTrusted: { false }, lanAddresses: { lan }
        )
        return try AppModel(dependencies: .test(clipboard: clipboard, systemProxy: systemProxy, devices: probe))
    }

    private func record(_ model: AppModel) async {
        model.proxy.toggleRunning()
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
    }

    @Test
    func theToneFollowsTheProxyState() async throws {
        let model = try model()
        #expect(model.statusBar.stateTone == .neutral)
        model.proxy.toggleRunning()
        #expect(model.statusBar.stateTone == .warning)
        #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
        #expect(model.statusBar.stateTone == .done)
    }

    @Test
    func aFailedStartHasTheErrorTone() throws {
        let model = try model()
        model.settings.port = 0
        model.proxy.toggleRunning()
        #expect(model.statusBar.stateTone == .error)
    }

    @Test(arguments: [
        (true, true, "192.168.1.5:9123", true), (true, false, nil, true), (false, true, nil, true),
        (true, true, nil, false),
    ])
    func theAddressShowsOnlyWhileRecordingForTheNetwork(
        running: Bool, everywhere: Bool, expected: String?, hasAddress: Bool
    ) async throws {
        let model = try model(lan: hasAddress ? ["192.168.1.5"] : [])
        model.settings.listenOnAllInterfaces = everywhere
        if running {
            await record(model)
        }
        #expect(model.statusBar.lanAddress == expected)
    }

    @Test
    func copyingTheAddressPutsItOnTheClipboardWithANotice() async throws {
        let clipboard = ClipboardSpy()
        let model = try model(clipboard: clipboard)
        model.settings.listenOnAllInterfaces = true
        await record(model)
        model.statusBar.copyLanAddress()
        #expect(clipboard.string() == "192.168.1.5:9123")
        #expect(model.notices.notice?.message == "Device address copied")
    }

    @Test
    func copyingWithoutAnAddressDoesNothing() throws {
        let clipboard = ClipboardSpy()
        let model = try model(clipboard: clipboard)
        model.statusBar.copyLanAddress()
        #expect(clipboard.string() == nil)
    }

    @Test
    func theSystemProxyItemSaysWhatClickingDoes() async throws {
        let model = try model()
        await record(model)
        #expect(model.statusBar.systemProxyText == "System proxy off")
        #expect(model.statusBar.systemProxyTone == .neutral)
        model.statusBar.toggleSystemProxy()
        #expect(await eventually { model.proxy.systemProxyOn })
        #expect(model.statusBar.systemProxyText == "System proxy on")
        #expect(model.statusBar.systemProxyTone == .done)
        #expect(model.statusBar.systemProxyHelp.contains("Click to turn off"))
    }

    @Test
    func clickingTheSystemProxyWhileTheProxyIsSwitchingDoesNothing() async throws {
        let model = try model()
        await record(model)
        model.proxy.toggleRunning()
        model.statusBar.toggleSystemProxy()
        #expect(await eventually { !model.proxy.isSwitchingProxy })
        #expect(!model.proxy.systemProxyOn)
        #expect(systemProxy.calls.isEmpty)
    }

    @Test
    func clickingTheSystemProxyWhileStoppedAsksToStartTheProxy() throws {
        let model = try model()
        model.statusBar.toggleSystemProxy()
        #expect(model.notices.notice?.message == "Start the proxy first.")
        #expect(model.notices.notice?.kind == .error)
        #expect(!model.proxy.systemProxyOn)
        #expect(systemProxy.calls.isEmpty)
    }

    @Test(arguments: [
        ([String](), [String](), "HTTPS: not decrypted", false), (["*"], [], "HTTPS decrypted", true),
        (["*"], ["a.test"], "HTTPS: all but 1 host", false), (["a.test"], [], "HTTPS: 1 host", false),
        (["a.test", "b.test"], [], "HTTPS: 2 hosts", false),
    ])
    func theHTTPSItemFollowsTheSSLProxyingRules(include: [String], exclude: [String], text: String, all: Bool) throws {
        let model = try model()
        model.settings.sslProxying = SSLProxyingSettings(include: include, exclude: exclude)
        #expect(model.statusBar.https == StatusBarText.HTTPS(text: text, decryptsAll: all))
    }

    @Test
    func toolsAreListedByNameAndCountedWhenSeveral() throws {
        let model = try model()
        #expect(model.statusBar.activeTools.isEmpty)
        model.settings.noCaching = true
        #expect(model.statusBar.toolsText == "No Caching")
        #expect(model.statusBar.toolsHelp == "Changing traffic: No Caching. Click to open Tools (⌘T).")
        let rule = BlockRule(name: "a", matching: .init(pattern: "a"))
        model.settings.blockList = RuleSet(isEnabled: true, rules: [rule])
        #expect(model.statusBar.toolsText == "2 tools on")
    }

    @Test
    func pausedRequestsAreCounted() throws {
        let model = try model()
        #expect(model.statusBar.pausedCount == 0)
        model.breakpoints.changed([.init(phase: .request, request: .fixture())])
        #expect(model.statusBar.pausedText == "1 paused")
    }

    @Test
    func theSummaryCountsVisibleOfAllWithTheirSize() throws {
        let model = try AppModel.demo()
        let summary = model.statusBar.summary
        #expect(summary.hasPrefix("5 of 5 · "))
    }

    @Test
    func thePanelsLineIsTheModelsStatusLine() throws {
        let model = try model()
        #expect(model.statusBar.line == model.statusLine)
    }

    @Test
    func clickingItemsOpensTheirSheets() throws {
        let model = try model()
        model.statusBar.showSSLProxying()
        #expect(model.router.sheet == .tools)
        #expect(model.router.toolsSelection == .sslProxying)
        model.router.sheet = nil
        model.statusBar.showBreakpoints()
        #expect(model.router.sheet == .breakpoints)
        model.router.sheet = nil
        model.statusBar.showTools()
        #expect(model.router.sheet == .tools)
    }
}
