import Foundation

/// Facade the app and CLI drive: owns the proxy, the session, breakpoints and settings.
public final class WatcherEngine: @unchecked Sendable {
    public let store = FlowStore()
    public let breakpoints = BreakpointCenter()
    public let settings: SettingsStore
    public let authority: CertificateAuthority
    public let workspaces: WorkspaceStore

    /// Receives script `console.log` output and non-fatal problems (e.g. a busy reverse-proxy port).
    public var onLog: @Sendable (String) -> Void = { _ in }

    private var server: ProxyServer?
    private var watcher: Task<Void, Never>?
    private var appliedReverseProxies: [ReverseProxyRule]?
    private var appliedSocks: SocksSettings?
    private let previewers = PreviewerRunner()
    private var protobufSchema: (files: [String], schema: ProtobufSchema?) = ([], nil)
    private var loadedPAC: (location: String, evaluator: PACEvaluator)?

    public init(directory: URL = WatcherPaths.supportDirectory) throws {
        authority = try CertificateAuthority(directory: directory)
        settings = SettingsStore(url: directory.appendingPathComponent("settings.json"))
        workspaces = WorkspaceStore(directory: directory.appendingPathComponent("workspaces", isDirectory: true))
    }

    /// Starts listening on the configured port (or `port`) and returns the bound port.
    @discardableResult
    public func start(port: Int? = nil) async throws -> Int {
        // A stopped ProxyServer cannot be restarted, so every start gets a fresh one.
        let server = ProxyServer(store: store, authority: authority)
        let current = settings.value
        let host = current.listenOnAllInterfaces ? (current.listenOnIPv6 ? "::" : "0.0.0.0") : "127.0.0.1"
        let wanted = port ?? current.port
        let bound: Int
        do { bound = try await server.start(host: host, port: wanted) }
        catch where current.autoSelectPort && wanted != 0 { bound = try await server.start(host: host, port: 0) }
        self.server = server
        boundPort = bound
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
        appliedReverseProxies = nil; appliedSocks = nil
        await apply(settings.value)
        watcher = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                if let self, settings.reloadIfChanged() {
                    await apply(settings.value)
                }
            }
        }
        return bound
    }

    public func stop() async throws {
        watcher?.cancel()
        breakpoints.releaseAll()
        try await server?.stop()
        server = nil; boundPort = nil
    }

    public var isRunning: Bool {
        server != nil
    }

    /// While false, requests are still proxied but not listed.
    public var isRecording: Bool {
        get { store.isRecording }
        set { store.isRecording = newValue }
    }

    /// The port the proxy is actually listening on (differs from the setting when it was busy or 0).
    public private(set) var boundPort: Int?

    /// Pushes settings into the live proxy; does nothing while stopped (start applies them).
    public func apply(_ settings: WatcherSettings) async {
        guard let server else { return }
        let log = onLog
        loadProtobufSchemas(settings.protobufSchemas, log: log)
        server.tools.set(ToolFactory.makeTools(from: settings, breakpoints: breakpoints, log: { log($0) }))
        if !settings.breakpoints.isEnabled {
            breakpoints.releaseAll()
        }
        server.updatePolicies(settings)
        store.maxFlows = settings.maxFlows
        server.sslProxying = HostFilter(include: settings.sslProxying.include, exclude: settings.sslProxying.exclude)
        await server.updateUpstream(
            external: settings.externalProxy,
            pac: pacEvaluator(for: settings.externalProxy, log: log),
            dnsRules: settings.dnsSpoofing.active,
            certificates: settings.customCertificates.active
        )
        if settings.socks != appliedSocks {
            appliedSocks = settings.socks
            if let failure = await server.setSocks(settings.socks, host: settings.listenOnAllInterfaces ? "0.0.0.0" : "127.0.0.1") {
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
        guard let server else { return ProxyServer.message(503, "Watcher is not running") }
        var current = request
        let seconds = timeout ?? settings.value.composeTimeoutSeconds
        var response = await server.process(current, timeout: seconds)
        for _ in 0 ..< 10 where followRedirects {
            guard [301, 302, 303, 307, 308].contains(response.status),
                  let location = response.headers.value(for: "location"),
                  let target = URL(string: location, relativeTo: URL(string: current.url)),
                  let components = URLComponents(url: target.absoluteURL, resolvingAgainstBaseURL: true), let host = components.host else { break }
            let scheme = components.scheme ?? current.scheme
            let changesMethod = response.status == 303 || ((response.status == 301 || response.status == 302) && current.method == "POST")
            current = RequestRecord(
                method: changesMethod ? "GET" : current.method, scheme: scheme, host: host,
                port: components.port ?? RequestRecord.defaultPort(for: scheme),
                path: (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath) + (components.percentEncodedQuery.map { "?\($0)" } ?? ""),
                headers: current.headers.filter { $0.name.lowercased() != "host" && !(changesMethod && $0.name.lowercased().hasPrefix("content-")) },
                body: changesMethod ? Data() : current.body
            )
            response = await server.process(current, timeout: seconds)
        }
        return response
    }

    /// Reads all `.desc` files into one schema; unreadable files are reported and skipped.
    private func loadProtobufSchemas(_ files: [String], log: @Sendable (String) -> Void) {
        guard files != protobufSchema.files else { return }
        var combined = Data()
        for file in files {
            do { try combined.append(Data(contentsOf: URL(fileURLWithPath: (file as NSString).expandingTildeInPath)))
                // A FileDescriptorSet is a repeated field, so concatenated sets are themselves a valid set.
            } catch { log("Protobuf schema \(file): \(error)") }
        }
        let schema = combined.isEmpty ? nil : try? ProtobufSchema(descriptorSet: combined)
        if !files.isEmpty, schema == nil {
            log("Protobuf schemas could not be parsed")
        }
        protobufSchema = (files, schema)
    }

    /// Body text for display: a schema-decoded protobuf when a rule names the message type, else the generic preview.
    public func bodyText(of flow: Flow, response: Bool) -> String {
        let data = response ? flow.response?.body ?? Data() : flow.request.body
        let headers = response ? flow.response?.headers ?? [] : flow.request.headers
        let contentType = headers.value(for: "content-type")
        if let schema = protobufSchema.schema,
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

    private func pacEvaluator(for external: ExternalProxySettings, log: @Sendable (String) -> Void) async -> PACEvaluator? {
        guard external.isEnabled, external.kind == .pac, !external.pacURL.isEmpty else { return nil }
        if let loaded = loadedPAC, loaded.location == external.pacURL {
            return loaded.evaluator
        }
        do {
            let evaluator = try await PACEvaluator.load(from: external.pacURL)
            loadedPAC = (external.pacURL, evaluator)
            return evaluator
        } catch {
            log("PAC: \(error)")
            return nil
        }
    }
}
