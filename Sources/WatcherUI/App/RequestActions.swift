import AppKit
import Observation
import WatcherCore

/// What the list, inspector and menus do with captured requests: star, comment, delete, repeat, copy, mock and
/// compare them.
@MainActor @Observable
final class RequestActions {
    private let store: FlowStore
    private let sender: any RequestSending
    private let previewers: @Sendable (Flow) async -> [PreviewOutput]
    private let clipboard: any Clipboard
    private let workspace: any WorkspaceOpener
    private let paths: SupportPaths
    private let files: FileAccess
    private let settings: SettingsEditor
    private let notices: NoticeCenter
    private let router: WindowRouter
    private let list: FlowListViewModel
    private let proxy: ProxyController

    struct Services {
        var sender: any RequestSending
        var previews: @Sendable (Flow) async -> [PreviewOutput]
        var clipboard: any Clipboard
        var workspace: any WorkspaceOpener
        var paths: SupportPaths
        var files: FileAccess
    }

    init(
        services: Services,
        store: FlowStore,
        settings: SettingsEditor,
        notices: NoticeCenter,
        router: WindowRouter,
        list: FlowListViewModel,
        proxy: ProxyController
    ) {
        sender = services.sender; previewers = services.previews; clipboard = services.clipboard
        workspace = services.workspace; paths = services.paths; files = services.files
        self.store = store; self.settings = settings; self.notices = notices
        self.router = router; self.list = list; self.proxy = proxy
    }

    /// Clearing can drop thousands of requests at once, so the notice offers Undo for a few seconds.
    func clear() {
        let removed = store.clear()
        guard !removed.isEmpty else { return notices.notify("Session cleared") }
        let undo = NoticeAction(title: "Undo") { [store, notices] in
            store.restore(removed)
            notices.notify("Requests restored", .success)
        }
        notices.notify("Cleared \(removed.count) request\(removed.count == 1 ? "" : "s")", action: undo)
    }

    func toggleStar(_ ids: Set<Flow.ID>) {
        let targets = list.flows.filter { ids.contains($0.id) }
        let star = targets.contains { !$0.isStarred }
        for flow in targets {
            store.annotate(flow.id, starred: star)
        }
        notices.notify(star ? "Starred" : "Star removed")
    }

    func setComment(_ comment: String, for id: Flow.ID) {
        store.annotate(id, comment: .some(comment))
    }

    func delete(_ ids: Set<Flow.ID>) {
        store.discard(ids)
    }

    /// Re-sends a captured request; with the setting on, cache validators are dropped so the server answers afresh.
    func repeatRequest(_ request: RequestRecord) {
        send(settings.noCachingOnRepeat ? request.droppingCacheValidators() : request)
    }

    func send(_ request: RequestRecord, followRedirects: Bool = false) {
        guard proxy.isRunning else { return notices.notify("Start the proxy to send requests.", .error) }
        Task {
            let response = await sender.send(request, followRedirects: followRedirects)
            let kind: Notice.Kind = response.status < 400 ? .success : .error
            notices.notify("\(request.method) \(request.host) → \(response.status)", kind)
        }
    }

    /// Sends and waits for the answer, for Compose to show inline.
    func perform(_ request: RequestRecord, followRedirects: Bool) async -> ResponseRecord {
        await sender.send(request, followRedirects: followRedirects)
    }

    func composeWebSocket(url: URL, headers: [Header], messages: [String]) {
        Task {
            do {
                try await sender.composeWebSocket(url: url, headers: headers, messages: messages)
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

    /// Code for a request; with "Add the proxy to copied cURL commands" on, cURL goes through Watcher again and
    /// trusts its certificate.
    func code(
        for request: RequestRecord,
        as language: CodeGenerator.Language = .curl,
        multiline: Bool = false
    ) -> String {
        let proxyURL = settings.includeProxyInCURL ? "http://127.0.0.1:\(proxy.port)" : nil
        let certificate = paths.certificateURL.path
        return CodeGenerator.generate(
            request, as: language, proxy: proxyURL, certificate: certificate, multiline: multiline
        )
    }

    /// File ▸ New Request from cURL: the command on the clipboard opens in Compose, ready to change and send.
    func composeFromClipboardCurl() {
        guard let text = clipboard.string(), CurlImport.looksLikeCurl(text) else {
            return notices.notify("Copy a curl command first, then choose New Request from cURL.", .error)
        }
        do {
            try router.compose(CurlImport.parse(text), from: nil)
        } catch { notices.notify("Cannot read the cURL command: \(error)", .error) }
    }

    /// Opens Compose filled with the captured request so it can be changed before sending.
    func editAndRepeat(_ flow: Flow) {
        router.compose(flow.request, from: flow)
    }

    /// After an edited request was sent: compare its answer (the newest call to that URL) with the original's.
    func compareWithOriginal(_ original: Flow, sent request: RequestRecord) {
        let resent = list.flows.last {
            $0.sequence > original.sequence && $0.request.method == request.method && $0.request.url == request.url
        }
        if let resent {
            list.selection = resent.id
        }
        router.sheet = nil
        router.compare(withBase: original)
    }

    /// Saves the response as an editable file and adds a Map Local rule that serves it for the same method and path.
    func mockResponse(_ flow: Flow) {
        do {
            let mock = try MockMaker.make(from: flow, in: paths.mocksDirectory, files: files)
            settings.mapLocal.isEnabled = true
            settings.mapLocal.rules.append(mock.rule)
            let path = flow.request.path.split(separator: "?").first ?? ""
            let file = mock.file.lastPathComponent
            let message = "Mock created: \(flow.request.method) \(path) now answers from \(file). "
                + "Edit the file to change the answer; switch it off in Tools → Map Local."
            notices.notify(message, .success)
            workspace.open(mock.file)
        } catch { notices.notify("Cannot create the mock: \(error)", .error) }
    }

    /// Pauses this URL from now on: the host and path, any query.
    func addBreakpoint(for request: RequestRecord) {
        settings.breakpoints.isEnabled = true
        let matching = Self.breakpointMatching(for: request)
        settings.breakpoints.rules.append(BreakpointRule(name: request.host, matching: matching))
    }

    static func breakpointMatching(for request: RequestRecord) -> MatchingRule {
        let path = String(request.path.prefix { $0 != "?" })
        let escapedPath = path.isEmpty || path == "/" ? "/?" : NSRegularExpression.escapedPattern(for: path)
        let tail = escapedPath + #"(\?.*)?"#
        return MatchingRule(pattern: anchored(host: escapedHost(request.host), tail: tail), mode: .regex)
    }

    /// Blocks this host only.
    func blockHost(_ host: String) {
        addBlockRule(name: host, matching: Self.hostMatching(host, subdomains: false))
    }

    /// Blocks a sidebar domain and its subdomains.
    func blockDomain(_ domain: String) {
        addBlockRule(name: domain, matching: Self.hostMatching(domain, subdomains: true))
        notices.notify("Requests to \(domain) are now blocked (Tools ▸ Block List)", .success)
    }

    private func addBlockRule(name: String, matching: MatchingRule) {
        settings.blockList.isEnabled = true
        guard !settings.blockList.rules.contains(where: { $0.matching == matching }) else { return }
        settings.blockList.rules.append(BlockRule(name: name, matching: matching))
    }

    /// The host is anchored at both ends, so a look-alike name or a URL that only mentions it never matches.
    private static func hostMatching(_ host: String, subdomains: Bool) -> MatchingRule {
        let name = (subdomains ? #"([^/?:]+\.)?"# : "") + escapedHost(host)
        return MatchingRule(pattern: anchored(host: name, tail: #"([/?].*)?"#), mode: .regex)
    }

    private static func escapedHost(_ host: String) -> String {
        NSRegularExpression.escapedPattern(for: host)
    }

    private static func anchored(host: String, tail: String) -> String {
        #"^([A-Za-z][A-Za-z0-9+.-]*://)?"# + host + #"(:\d+)?"# + tail + "$"
    }

    /// Output of every enabled previewer whose URL pattern matches this request.
    func previews(for flow: Flow) async -> [PreviewOutput] {
        await previewers(flow)
    }

    func revealCertificate() {
        workspace.reveal([paths.certificateURL])
    }
}
