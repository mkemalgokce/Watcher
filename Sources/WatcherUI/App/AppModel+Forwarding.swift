import AppKit
import WatcherCore

/// Shortcuts the views still use while they move to the child view models.
extension AppModel {
    var sheet: Sheet? {
        get { router.sheet }
        set { router.sheet = newValue }
    }

    var toolsSelection: ToolsView.Tool {
        get { router.toolsSelection }
        set { router.toolsSelection = newValue }
    }

    var exchangeSide: MessageSide {
        get { router.exchangeSide }
        set { router.exchangeSide = newValue }
    }

    var askWorkspaceName: Bool {
        get { router.askWorkspaceName }
        set { router.askWorkspaceName = newValue }
    }

    var composeDraft: RequestRecord? {
        get { router.composeDraft }
        set { router.composeDraft = newValue }
    }

    var composeSource: Flow? {
        get { router.composeSource }
        set { router.composeSource = newValue }
    }

    var hidePingPong: Bool {
        get { router.hidePingPong }
        set { router.hidePingPong = newValue }
    }

    var diffBase: Flow? {
        get { router.diffBase }
        set { router.diffBase = newValue }
    }

    var searchFocusRequest: Int {
        router.searchFocusRequest
    }

    var compareWindowRequest: Int {
        router.compareWindowRequest
    }

    func show(_ sheet: Sheet) {
        router.show(sheet)
    }

    func requestSearchFocus() {
        router.requestSearchFocus()
    }

    func compare(withBase flow: Flow) {
        router.compare(withBase: flow)
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

    var proxyPort: Int {
        proxy.port
    }

    func toggleRunning() {
        proxy.toggleRunning()
    }

    func setSystemProxy(_ enabled: Bool) {
        proxy.setSystemProxy(enabled)
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

    var hits: [BreakpointCenter.Hit] {
        breakpoints.hits
    }

    func breakpointRules(matching request: RequestRecord) -> [BreakpointRule] {
        breakpoints.rules(matching: request)
    }

    func removeBreakpoints(for hit: BreakpointCenter.Hit) {
        breakpoints.removeBreakpoints(for: hit)
    }

    func resolve(_ hit: BreakpointCenter.Hit, with resolution: BreakpointCenter.Resolution) {
        breakpoints.resolve(hit, with: resolution)
    }

    func clear() {
        actions.clear()
    }

    func toggleStar(_ ids: Set<Flow.ID>) {
        actions.toggleStar(ids)
    }

    func setComment(_ comment: String, for id: Flow.ID) {
        actions.setComment(comment, for: id)
    }

    func delete(_ ids: Set<Flow.ID>) {
        actions.delete(ids)
    }

    func repeatRequest(_ request: RequestRecord) {
        actions.repeatRequest(request)
    }

    func send(_ request: RequestRecord, followRedirects: Bool = false) {
        actions.send(request, followRedirects: followRedirects)
    }

    func perform(_ request: RequestRecord, followRedirects: Bool) async -> ResponseRecord {
        await actions.perform(request, followRedirects: followRedirects)
    }

    func composeWebSocket(url: URL, headers: [Header], messages: [String]) {
        actions.composeWebSocket(url: url, headers: headers, messages: messages)
    }

    func copy(_ text: String, _ what: String = "Copied") {
        actions.copy(text, what)
    }

    func copy(image: NSImage) {
        actions.copy(image: image)
    }

    func code(
        for request: RequestRecord,
        as language: CodeGenerator.Language = .curl,
        multiline: Bool = false
    ) -> String {
        actions.code(for: request, as: language, multiline: multiline)
    }

    func composeFromClipboardCurl() {
        actions.composeFromClipboardCurl()
    }

    func editAndRepeat(_ flow: Flow) {
        actions.editAndRepeat(flow)
    }

    func compareWithOriginal(_ original: Flow, sent request: RequestRecord) {
        actions.compareWithOriginal(original, sent: request)
    }

    func mockResponse(_ flow: Flow) {
        actions.mockResponse(flow)
    }

    func revealCertificate() {
        actions.revealCertificate()
    }

    var lanProxyAddress: String? {
        devices.lanProxyAddress
    }

    func setAndroidProxy(_ device: AndroidDevice, enabled: Bool) {
        Task { await devices.setProxy(on: device, enabled: enabled) }
    }
}
