import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WatcherCore

/// View state for the whole window; the proxy itself lives in `WatcherEngine`.
@MainActor @Observable
public final class AppModel {
    let engine: WatcherEngine
    @ObservationIgnored let clipboard: any Clipboard
    let notices: NoticeCenter
    @ObservationIgnored let preferences: any Preferences
    let sessionFiles: SessionFilesViewModel
    /// Certificate trust and device setup (DeviceSetupView, the welcome sheet and the first-run list). Previews and tests
    /// get a probe that never asks the keychain, simctl or adb, so what they show is the same on every Mac.
    let devices: DevicesViewModel
    let list: FlowListViewModel
    /// Settable inside the module so previews can show paused traffic.
    internal(set) var hits: [BreakpointCenter.Hit] = []
    let proxy: ProxyController
    private(set) var workspaces: [String] = []
    /// The dialog currently shown over the main window; menus and toolbar both open it through here.
    var sheet: Sheet?
    /// The page Tools opens on; callers set it to land on the tool they mean.
    var toolsSelection = ToolsView.Tool.sslProxying
    /// The half of the exchange shown when the inspector is too narrow for both side by side.
    var exchangeSide = MessageSide.response
    /// Bumped to move keyboard focus into the request filter field (⌘F outside a body).
    private(set) var searchFocusRequest = 0
    func requestSearchFocus() {
        searchFocusRequest += 1
        if #unavailable(macOS 15.0), let window = NSApp.keyWindow {
            Find.focusFilter(in: window)
        }
    }

    var askWorkspaceName = false
    /// Set once the first-run setup has been completed or skipped.
    var onboardingDone: Bool {
        didSet { preferences.onboardingDone = onboardingDone }
    }

    /// Request to pre-fill the compose window with (Edit & Repeat).
    var composeDraft: RequestRecord?
    /// The captured flow an Edit & Repeat started from, so Compose can show what changed and compare the answers.
    var composeSource: Flow?

    /// Hide WebSocket ping/pong control frames in the message list.
    var hidePingPong = true
    /// Flow that the Compare window holds the selection against.
    var diffBase: Flow?
    /// Bumped to bring the Compare window forward; the main window turns it into openWindow, which only views can call.
    private(set) var compareWindowRequest = 0

    /// Remembers `flow` as the base and opens Compare, which then follows whatever is selected in the list.
    func compare(withBase flow: Flow) {
        diffBase = flow
        compareWindowRequest += 1
        notices.notify("#\(flow.sequence) is the compare base. Select another request to compare.")
    }

    var settings: SettingsEditor

    public convenience init() {
        self.init(listening: true)
    }

    /// `listening: false` leaves the model static, for previews that fill it by hand.
    convenience init(listening: Bool) {
        self.init(dependencies: listening ? .live() : .preview(), listening: listening)
    }

    init(dependencies: AppDependencies, listening: Bool = false) {
        engine = dependencies.engine
        clipboard = dependencies.clipboard
        preferences = dependencies.preferences
        onboardingDone = dependencies.preferences.onboardingDone
        let notices = NoticeCenter(sleep: dependencies.sleep, announce: dependencies.announce)
        self.notices = notices
        sessionFiles = SessionFilesViewModel(
            panels: dependencies.panels,
            files: dependencies.files,
            commands: dependencies.commands,
            store: dependencies.engine.store,
            notices: notices
        )
        devices = DevicesViewModel(probe: listening ? .live : .none, certificateURL: WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem"))
        let settings = SettingsEditor(engine: engine, sleep: dependencies.sleep, notices: notices)
        self.settings = settings
        workspaces = engine.workspaces.list()
        proxy = ProxyController(runner: dependencies.runner, systemProxy: dependencies.systemProxy, notices: notices) {
            settings.value
        }
        proxy.restoreLeftoverSystemProxy()
        dependencies.onTerminate { [proxy] in proxy.applicationWillTerminate() }

        let list = FlowListViewModel(store: engine.store, sleep: dependencies.sleep)
        list.hidesAppleTraffic = settings.hideAppleTraffic
        settings.onChange = { [list] _, new in list.hidesAppleTraffic = new.hideAppleTraffic }
        self.list = list
        if listening {
            observeEngine()
        }
    }

    /// Follows the store and paused breakpoints; separate from init so tests can watch a model that has no system side effects.
    func observeEngine() {
        list.observeStore()
        let breakpointChanges = engine.breakpoints.changes()
        Task { for await _ in breakpointChanges {
            self.breakpointsChanged(self.engine.breakpoints.pending)
        } }
    }

    enum Sheet: Identifiable {
        case tools, breakpoints, compose, devices, welcome, converter, help
        var id: Self {
            self
        }
    }

    func show(_ sheet: Sheet) {
        self.sheet = sheet
    }

    /// The line under the window title: starting, listening (with the address), stopped, or that starting failed.
    var statusLine: String {
        proxy.status(listing: list.countText)
    }

    var isRunning: Bool {
        proxy.isRunning
    }

    var isSwitchingProxy: Bool {
        proxy.isSwitchingProxy
    }

    var proxyError: String? {
        proxy.proxyError
    }

    var systemProxyOn: Bool {
        proxy.systemProxyOn
    }

    func toggleRunning() {
        proxy.toggleRunning()
    }

    func setSystemProxy(_ on: Bool) {
        proxy.setSystemProxy(on)
    }

    /// Code for a request; with "Add the proxy to copied cURL commands" on, cURL goes through Watcher again and trusts its certificate.
    func code(for request: RequestRecord, as language: CodeGenerator.Language = .curl, multiline: Bool = false) -> String {
        let proxy = settings.includeProxyInCURL ? "http://127.0.0.1:\(proxyPort)" : nil
        return CodeGenerator.generate(request, as: language, proxy: proxy, certificate: engine.authority.certificateURL.path, multiline: multiline)
    }

    /// The port the proxy listens on: the one it bound while running, otherwise the configured one.
    var proxyPort: Int {
        proxy.port
    }

    var flows: [Flow] {
        list.flows
    }

    var visibleFlows: [Flow] {
        list.visibleFlows
    }

    var counts: SidebarCounts {
        list.counts
    }

    var visibleBytes: Int {
        list.visibleBytes
    }

    var selection: Flow.ID? {
        get { list.selection }
        set { list.selection = newValue }
    }

    var query: FlowFilter {
        get { list.query }
        set { list.query = newValue }
    }

    var sidebar: SidebarItem {
        get { list.sidebar }
        set { list.sidebar = newValue }
    }

    var sortOrder: [KeyPathComparator<Flow>] {
        get { list.sortOrder }
        set { list.sortOrder = newValue }
    }

    var selectedFlow: Flow? {
        list.selectedFlow
    }

    func enqueue(_ event: FlowEvent) {
        list.enqueue(event)
    }

    func flushEvents() {
        list.flushEvents()
    }

    func syncFromStore() {
        list.syncFromStore()
    }

    /// End of the welcome screen: remember the choice, then start capturing.
    func finishOnboarding() {
        onboardingDone = true
        sheet = nil
        if !isRunning {
            toggleRunning()
        }
    }

    /// Clearing can drop thousands of requests at once, so the notice offers Undo for a few seconds.
    func clear() {
        let removed = engine.store.clear()
        guard !removed.isEmpty else { return notices.notify("Session cleared") }
        let undo = NoticeAction(title: "Undo") { [weak self] in
            self?.engine.store.restore(removed)
            self?.notices.notify("Requests restored", .success)
        }
        notices.notify("Cleared \(removed.count) request\(removed.count == 1 ? "" : "s")", action: undo)
    }

    func saveWorkspace(named name: String) {
        do {
            try engine.saveWorkspace(named: name)
            workspaces = engine.workspaces.list()
        } catch { notices.notify("\(error)", .error) }
    }

    func openWorkspace(_ name: String) {
        Task {
            do {
                try await engine.openWorkspace(named: name)
                settings.value = engine.settings.value
            } catch { notices.notify("\(error)", .error) }
        }
    }

    func revealCertificate() {
        NSWorkspace.shared.activateFileViewerSelecting([WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem")])
    }

    // MARK: Requests

    /// Re-sends a captured request; with the setting on, cache validators are dropped so the server answers afresh.
    /// File ▸ New Request from cURL: the command on the clipboard opens in Compose, ready to change and send.
    func composeFromClipboardCurl() {
        guard let text = clipboard.string(), CurlImport.looksLikeCurl(text) else {
            return notices.notify("Copy a curl command first, then choose New Request from cURL.", .error)
        }
        do {
            composeDraft = try CurlImport.parse(text)
            composeSource = nil
            show(.compose)
        } catch { notices.notify("Cannot read the cURL command: \(error)", .error) }
    }

    func repeatRequest(_ request: RequestRecord) {
        send(settings.noCachingOnRepeat ? request.droppingCacheValidators() : request)
    }

    /// Opens Compose filled with the captured request so it can be changed before sending.
    func editAndRepeat(_ flow: Flow) {
        composeDraft = flow.request
        composeSource = flow
        sheet = .compose
    }

    /// After an edited request was sent: compare its answer (the newest call to that URL) with the original's.
    func compareWithOriginal(_ original: Flow, sent request: RequestRecord) {
        if let resent = flows.last(where: { $0.sequence > original.sequence && $0.request.method == request.method && $0.request.url == request.url }) {
            selection = resent.id
        }
        sheet = nil
        compare(withBase: original)
    }

    /// Saves the response as an editable file and adds a Map Local rule that serves it for the same method and path.
    func mockResponse(_ flow: Flow) {
        do {
            let mock = try MockMaker.make(from: flow, in: WatcherPaths.supportDirectory.appendingPathComponent("mocks", isDirectory: true))
            settings.mapLocal.isEnabled = true
            settings.mapLocal.rules.append(mock.rule)
            let path = flow.request.path.split(separator: "?").first ?? ""
            let file = mock.file.lastPathComponent
            let message = "Mock created: \(flow.request.method) \(path) now answers from \(file). "
                + "Edit the file to change the answer; switch it off in Tools → Map Local."
            notices.notify(message, .success)
            NSWorkspace.shared.open(mock.file)
        } catch { notices.notify("Cannot create the mock: \(error)", .error) }
    }

    func toggleStar(_ ids: Set<Flow.ID>) {
        let targets = flows.filter { ids.contains($0.id) }
        let star = targets.contains { !$0.isStarred }
        for flow in targets {
            engine.store.annotate(flow.id, starred: star)
        }
        notices.notify(star ? "Starred" : "Star removed")
    }

    func setComment(_ comment: String, for id: Flow.ID) {
        engine.store.annotate(id, comment: .some(comment))
    }

    func delete(_ ids: Set<Flow.ID>) {
        engine.store.discard(ids)
    }

    /// Sends and waits for the answer, for Compose to show inline.
    func perform(_ request: RequestRecord, followRedirects: Bool) async -> ResponseRecord {
        await engine.send(request, followRedirects: followRedirects)
    }

    func send(_ request: RequestRecord, followRedirects: Bool = false) {
        guard isRunning else { return notices.notify("Start the proxy to send requests.", .error) }
        Task {
            let response = await engine.send(request, followRedirects: followRedirects)
            let kind: Notice.Kind = response.status < 400 ? .success : .error
            notices.notify("\(request.method) \(request.host) → \(response.status)", kind)
        }
    }

    func composeWebSocket(url: URL, headers: [Header], messages: [String]) {
        Task {
            do {
                try await engine.composeWebSocket(url: url, headers: headers, messages: messages)
            } catch { notices.notify("\(error)", .error) }
        }
    }

    func copy(_ text: String, _ what: String = "Copied") {
        clipboard.setString(text)
        notices.notify(what, .success)
    }

    func copy(image: NSImage) {
        clipboard.setImage(image)
        notices.notify("Image copied", .success)
    }

    /// New pauses are announced, never pushed into a window: opening Breakpoints on every hit took over the screen
    /// again right after an abort. The toolbar badge and status bar stay as the way in.
    func breakpointsChanged(_ pending: [BreakpointCenter.Hit]) {
        let added = pending.count - hits.count
        hits = pending
        if added > 0 {
            notices.notify("\(pending.count) paused at a breakpoint. Review with ⌘B, or remove the breakpoint there.")
        }
    }

    /// The breakpoint rules that stop this request.
    func breakpointRules(matching request: RequestRecord) -> [BreakpointRule] {
        settings.breakpoints.rules.filter { $0.isEnabled && RequestMatcher($0.matching).matches(request) }
    }

    /// Deletes the rules that stop `hit`'s request and lets it, and everything else they paused, continue.
    func removeBreakpoints(for hit: BreakpointCenter.Hit) {
        let doomed = breakpointRules(matching: hit.request)
        guard !doomed.isEmpty else { return resolve(hit, with: .proceed(request: hit.request, response: hit.response)) }
        settings.breakpoints.rules.removeAll { rule in doomed.contains { $0.matching == rule.matching && $0.name == rule.name } }
        // Whatever no remaining rule would stop is let through, so removing a breakpoint never leaves requests hanging.
        for paused in hits where breakpointRules(matching: paused.request).isEmpty {
            resolve(paused, with: .proceed(request: paused.request, response: paused.response))
        }
        let removed = doomed.count == 1
            ? "Breakpoint “\(doomed[0].displayName)” removed"
            : "\(doomed.count) breakpoints removed"
        notices.notify(removed, .success)
    }

    func resolve(_ hit: BreakpointCenter.Hit, with resolution: BreakpointCenter.Resolution) {
        engine.breakpoints.resolve(hit.id, with: resolution)
    }

    // MARK: Devices

    /// Address a phone on the same network should use as its proxy.
    var lanProxyAddress: String? {
        LocalNetwork.ipv4Addresses().first.map { "\($0.ip):\(proxyPort)" }
    }

    /// The proxy endpoint Android devices should use.
    func setAndroidProxy(_ device: AndroidDevice, enabled: Bool) {
        let lanAddress = LocalNetwork.ipv4Addresses().first?.ip
        Task { await devices.setProxy(on: device, enabled: enabled, port: proxyPort, lanAddress: lanAddress) }
    }
}
