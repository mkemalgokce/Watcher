import Foundation

/// Facade the app and CLI drive: owns the proxy, the session, breakpoints and settings.
public final class WatcherEngine: @unchecked Sendable {
    public let store = FlowStore()
    public let breakpoints = BreakpointCenter()
    public let settings: SettingsStore
    public let authority: CertificateAuthority
    public let workspaces: WorkspaceStore

    /// Receives script `console.log` output and non-fatal problems (e.g. a busy reverse-proxy port).
    public var onLog: @Sendable (String) -> Void {
        get { lock.withLock { logHandler } }
        set { lock.withLock { logHandler = newValue } }
    }

    /// False tunnels all HTTPS untouched whatever the stored settings say, without changing them; set it before `start`.
    public var decryptsHTTPS = true

    /// Guards `server`, `bound`, `protobufSchema` and `loadedPAC`, which callers reach from any thread.
    private let lock = NSLock()
    private var server: ProxyServer?
    private var bound: Int?
    private var logHandler: @Sendable (String) -> Void = { _ in }
    private var hostsReportedAbandoned: Set<String> = []
    /// The last queued start, stop or apply; each one waits for it, so they never interleave.
    private var lastStep: Task<Void, Never>?
    private var watcher: Task<Void, Never>?
    private var appliedReverseProxies: [ReverseProxyRule]?
    private var appliedSocks: SocksSettings?
    private let previewers = PreviewerRunner()
    private var protobufSchema: (files: [String], schema: ProtobufSchema?) = ([], nil)
    private var loadedPAC: (location: String, evaluator: PACEvaluator)?
    private let files: FileAccess
    private let pacLoader: @Sendable (String) async throws -> PACEvaluator
    private let sleep: Sleep
    private let pacTimeout: Duration
    let now: @Sendable () -> Date
    private let makeServer: @Sendable (FlowStore, CertificateAuthority) -> ProxyServer

    /// `makeServer` builds the proxy for each start; tests pass one with their own TLS trust or app lookup.
    /// `sleep` paces the check for settings edited outside the engine; `now` times composed WebSockets.
    public init(
        directory: URL = WatcherPaths.supportDirectory,
        files: FileAccess = .live,
        pacLoader: (@Sendable (String) async throws -> PACEvaluator)? = nil,
        pacTimeout: Duration = .seconds(10),
        sleep: @escaping Sleep = liveSleep,
        now: @escaping @Sendable () -> Date = { Date() },
        makeServer: @escaping @Sendable (FlowStore, CertificateAuthority) -> ProxyServer = {
            ProxyServer(store: $0, authority: $1)
        }
    ) throws {
        self.files = files; self.pacTimeout = pacTimeout; self.sleep = sleep
        self.now = now; self.makeServer = makeServer
        self.pacLoader = pacLoader ?? { try await PACEvaluator.load(from: $0) }
        authority = try CertificateAuthority(directory: directory, files: files)
        settings = SettingsStore(url: WatcherPaths.settingsFile(in: directory), files: files)
        workspaces = WorkspaceStore(
            directory: directory.appendingPathComponent("workspaces", isDirectory: true),
            files: files
        )
    }

    /// Starts listening on the configured port (or `port`) and returns the bound port; a running proxy is stopped first.
    @discardableResult
    public func start(port: Int? = nil) async throws -> Int {
        let pac = await pacEvaluator(for: settings.value.externalProxy)
        return try await inOrder { [self] in
            if lock.withLock({ server != nil }) {
                try await stopNow()
            }
            return try await startNow(port: port, pac: pac)
        }
    }

    /// Once per host, so clients that never trust the CA do not flood the log.
    private func reportAbandonedHandshake(of host: String) {
        guard lock.withLock({ hostsReportedAbandoned.insert(host).inserted }) else { return }
        onLog("\(host) abandoned the TLS handshake")
    }

    private func startNow(port: Int?, pac: PACEvaluator?) async throws -> Int {
        // A stopped ProxyServer cannot be restarted, so every start gets a fresh one.
        let server = makeServer(store, authority)
        let current = settings.value
        let host = Self.listenHost(for: current)
        let wanted = port ?? current.port
        server.onPinningSuspected = { [weak self] host in
            Task {
                try? await self?.updateSettings {
                    if !$0.sslProxying.exclude.contains(host) {
                        $0.sslProxying.exclude.append(host)
                    }
                }
                self?.onLog("\(host) rejected Watcher's certificate (pinning?); it is no longer decrypted")
            }
        }
        server.onHandshakeAbandoned = { [weak self] in self?.reportAbandonedHandshake(of: $0) }
        let bound: Int
        do {
            do {
                bound = try await server.start(host: host, port: wanted)
            } catch where current.autoSelectPort && wanted != 0 {
                bound = try await server.start(host: host, port: 0)
            }
        } catch {
            try? await server.stop()
            throw error
        }
        lock.withLock { self.server = server; self.bound = bound }
        appliedReverseProxies = nil; appliedSocks = nil
        await applyNow(settings.value, pac: pac)
        watcher = Task { [weak self, sleep] in
            while !Task.isCancelled {
                try? await sleep(.seconds(1))
                guard let self else { return }
                if settings.reloadIfChanged() {
                    await apply(settings.value)
                }
            }
        }
        return bound
    }

    public func stop() async throws {
        try await inOrder { [self] in try await stopNow() }
    }

    private func stopNow() async throws {
        watcher?.cancel()
        breakpoints.releaseAll()
        let server = lock.withLock { defer { self.server = nil; bound = nil }; return self.server }
        try await server?.stop()
    }

    /// Runs `step` once every start, stop and apply queued before it has finished.
    private func inOrder<T: Sendable>(_ step: @escaping @Sendable () async throws -> T) async throws -> T {
        let task = lock.withLock {
            let previous = lastStep
            let next = Task { await previous?.value; return try await step() }
            lastStep = Task { _ = try? await next.value }
            return next
        }
        return try await task.value
    }

    public var isRunning: Bool {
        lock.withLock { server != nil }
    }

    /// While false, requests are still proxied but not listed.
    public var isRecording: Bool {
        get { store.isRecording }
        set { store.isRecording = newValue }
    }

    /// The port the proxy is actually listening on (differs from the setting when it was busy or 0).
    public var boundPort: Int? {
        lock.withLock { bound }
    }

    /// How long Compose keeps a WebSocket open for replies, through the injected sleep.
    func waitWhileListening(_ duration: Duration) async throws {
        try await sleep(duration)
    }

    /// Pushes settings into the live proxy; does nothing while stopped (start applies them).
    /// The PAC script loads before queueing, so a slow download never holds up a stop or a start.
    public func apply(_ settings: WatcherSettings) async {
        let pac = isRunning ? await pacEvaluator(for: settings.externalProxy) : nil
        _ = try? await inOrder { [self] in await applyNow(settings, pac: pac) }
    }

    private func applyNow(_ settings: WatcherSettings, pac: PACEvaluator?) async {
        guard let server = lock.withLock({ server }) else { return }
        let log = onLog
        loadProtobufSchemas(settings.protobufSchemas, log: log)
        server.tools.set(ToolFactory.makeTools(from: settings, breakpoints: breakpoints, log: { log($0) }))
        if !settings.breakpoints.isEnabled {
            breakpoints.releaseAll()
        }
        server.updatePolicies(settings)
        store.maxFlows = settings.maxFlows
        let decrypted = settings.sslProxying
        server.sslProxying = HostFilter(include: decryptsHTTPS ? decrypted.include : [], exclude: decrypted.exclude)
        server.updateUpstream(
            external: settings.externalProxy,
            pac: pac,
            dnsRules: settings.dnsSpoofing.active,
            certificates: settings.customCertificates.active
        )
        if settings.socks != appliedSocks {
            appliedSocks = settings.socks
            if let failure = await server.setSocks(settings.socks, host: Self.listenHost(for: settings)) {
                log(failure)
            }
        }
        let reverse = settings.reverseProxy.active
        if reverse != appliedReverseProxies {
            appliedReverseProxies = reverse
            for failure in await server.setReverseProxies(reverse) {
                log(failure)
            }
        }
    }

    public func saveWorkspace(named name: String) throws {
        try workspaces.save(name: name, flows: store.all, settings: settings.value)
    }

    /// Replaces the session and the settings with the saved ones.
    public func openWorkspace(named name: String) async throws {
        let workspace = try workspaces.load(name: name)
        store.load(workspace.flows)
        try settings.replace(with: workspace.settings)
        await apply(workspace.settings)
    }

    /// Output of every enabled previewer whose URL pattern matches this request.
    public func previews(for flow: Flow) async -> [PreviewOutput] {
        let rules = settings.value.previewers.active
        guard !rules.isEmpty else { return [] }
        let log = onLog
        return await previewers.run(rules, for: flow) { log($0) }
    }

    /// A free local port for a new Reverse Proxy rule: the first one from 10000 that no rule, the proxy or SOCKS already uses.
    public func suggestReversePort() -> Int? {
        let current = settings.value
        let taken = Set(current.reverseProxy.rules.map(\.localPort) + [current.port, current.socks.port, boundPort].compactMap(\.self))
        return PortFinder.firstAvailable(avoiding: taken)
    }

    /// Edits settings, saves them and applies them to the running proxy in one step.
    public func updateSettings(_ change: (inout WatcherSettings) -> Void) async throws {
        try settings.update(change)
        await apply(settings.value)
    }

    /// Compose: sends a request through the pipeline (so tools apply and it is recorded) and returns the response.
    /// With `followRedirects`, each hop is a separate recorded request (up to 10).
    public func send(_ request: RequestRecord, followRedirects: Bool = false, timeout: Int? = nil) async -> ResponseRecord {
        guard let server = lock.withLock({ server }) else { return ProxyServer.message(503, "Watcher is not running") }
        var current = request
        let seconds = timeout ?? settings.value.composeTimeoutSeconds
        var response = await server.process(current, timeout: seconds)
        for _ in 0 ..< 10 where followRedirects {
            guard let next = RedirectHop.next(after: response, from: current) else { break }
            current = next
            response = await server.process(current, timeout: seconds)
        }
        return response
    }

    private func pacEvaluator(for external: ExternalProxySettings) async -> PACEvaluator? {
        guard external.isEnabled, external.kind == .pac, !external.pacURL.isEmpty else { return nil }
        if let loaded = lock.withLock({ loadedPAC }), loaded.location == external.pacURL {
            return loaded.evaluator
        }
        do {
            let (loader, location) = (pacLoader, external.pacURL)
            let evaluator = try await withTimeout(pacTimeout, "PAC download", sleep: sleep) {
                try await loader(location)
            }
            lock.withLock { loadedPAC = (external.pacURL, evaluator) }
            return evaluator
        } catch {
            onLog("PAC: \(error)")
            return nil
        }
    }
}

private extension WatcherEngine {
    static func listenHost(for settings: WatcherSettings) -> String {
        settings.listenOnAllInterfaces ? (settings.listenOnIPv6 ? "::" : "0.0.0.0") : "127.0.0.1"
    }
}

public extension WatcherEngine {
    /// The port the SOCKS5 listener is actually on while it runs (differs from the setting when that is 0).
    var socksPort: Int? {
        lock.withLock { server }?.socksPort
    }

    /// The ports of the running reverse-proxy listeners, in rule order.
    var reversePorts: [Int] {
        lock.withLock { server }?.reversePorts ?? []
    }
}

extension WatcherEngine {
    /// Reads all `.desc` files into one schema; unreadable files are reported and skipped.
    private func loadProtobufSchemas(_ paths: [String], log: @Sendable (String) -> Void) {
        let loaded = lock.withLock { protobufSchema }
        // A schema that failed to load is tried again, so a file that is fixed later is picked up.
        guard paths != loaded.files || (loaded.schema == nil && !paths.isEmpty) else { return }
        var combined = Data()
        for file in paths {
            do { try combined.append(files.read(URL(fileURLWithPath: (file as NSString).expandingTildeInPath)))
                // A FileDescriptorSet is a repeated field, so concatenated sets are themselves a valid set.
            } catch { log("Protobuf schema \(file): \(error)") }
        }
        let schema = combined.isEmpty ? nil : try? ProtobufSchema(descriptorSet: combined)
        if !paths.isEmpty, schema == nil {
            log("Protobuf schemas could not be parsed")
        }
        lock.withLock { protobufSchema = (paths, schema) }
    }

    /// Body text for display: a schema-decoded protobuf when a rule names the message type, else the generic preview.
    public func bodyText(of flow: Flow, response: Bool) -> String {
        let data = response ? flow.response?.body ?? Data() : flow.request.body
        let headers = response ? flow.response?.headers ?? [] : flow.request.headers
        let contentType = headers.value(for: "content-type")
        if let schema = lock.withLock({ protobufSchema.schema }),
           let rule = settings.value.protobuf.active.first(where: { $0.matching.compile().matches(flow.request) })
        {
            let type = response ? rule.responseType : rule.requestType
            let isGRPC = contentType?.lowercased().contains("grpc") == true && data.count > 5
            if !type.isEmpty, let text = schema.describe(isGRPC ? data.dropFirst(5) : data, as: type) {
                return text
            }
        }
        return BodyPreview.text(data, contentType: contentType)
    }
}
