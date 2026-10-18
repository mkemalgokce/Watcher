import Foundation

/// Model Context Protocol server (JSON-RPC 2.0, one message per line) that lets an AI agent inspect and drive Watcher.
/// Tool names are part of the interface: agent prompts refer to them, so they do not change.
public final class MCPServer: @unchecked Sendable {
    private struct ToolDefinition {
        let name: String
        let description: String
        let properties: [String: String] // argument name -> description (all strings unless noted by name)
        let required: [String]
        let run: ([String: Any]) async throws -> String
    }

    private struct Failure: Error, CustomStringConvertible { let description: String }

    private let engine: WatcherEngine
    private var tools: [ToolDefinition] = []
    private let localAddresses: @Sendable () -> [String]

    /// `localAddresses` are the Mac's LAN addresses that the status reports for pointing devices at the proxy.
    public init(
        engine: WatcherEngine,
        localAddresses: @escaping @Sendable () -> [String] = { LocalNetwork.ipv4Addresses().map(\.ip) }
    ) {
        self.engine = engine; self.localAddresses = localAddresses
        tools = definitions()
    }

    /// Handles one JSON-RPC line; returns the response line, or nil for notifications.
    public func handle(_ line: String) async -> String? {
        guard let data = line.data(using: .utf8), let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return response(id: NSNull(), error: (-32700, "Parse error"))
        }
        guard let id = message["id"] else { return nil }
        let params = message["params"] as? [String: Any] ?? [:]

        switch message["method"] as? String {
        case "initialize":
            return response(id: id, result: [
                "protocolVersion": params["protocolVersion"] as? String ?? "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "watcher", "version": "0.1.0"],
            ])
        case "ping":
            return response(id: id, result: [String: Any]())
        case "tools/list":
            return response(id: id, result: ["tools": tools.map(describe)])
        case "tools/call":
            guard let name = params["name"] as? String, let tool = tools.first(where: { $0.name == name }) else {
                return response(id: id, error: (-32602, "Unknown tool"))
            }
            let arguments = Self.stringArguments(params["arguments"] as? [String: Any] ?? [:])
            if let missing = tool.required.first(where: { (arguments[$0] as? String)?.isEmpty != false }) {
                return response(id: id, result: content("Missing required argument: \(missing)", isError: true))
            }
            do { return try await response(id: id, result: content(tool.run(arguments), isError: false)) }
            catch { return response(id: id, result: content("\(error)", isError: true)) }
        default:
            return response(id: id, error: (-32601, "Method not found"))
        }
    }

    /// Agents often send numbers where a string is declared; they are read as their text. Booleans and structures are not
    /// arguments, so a tool that needs them reports the argument as missing.
    private static func stringArguments(_ raw: [String: Any]) -> [String: Any] {
        raw.compactMapValues { value in
            switch value {
            case let text as String: text
            case let number as NSNumber where CFGetTypeID(number) != CFBooleanGetTypeID():
                Int(exactly: number.doubleValue).map(String.init) ?? number.stringValue
            default: nil
            }
        }
    }

    // MARK: Tools

    private static func status(of engine: WatcherEngine, lan: [String]) -> String {
        let port = engine.boundPort.map(String.init) ?? "-"
        return "running: \(engine.isRunning), port: \(port), requests captured: \(engine.store.all.count), "
            + "lan: \(lan.joined(separator: ", "))"
    }

    private static func mapRemoteRule(_ args: [String: Any]) throws -> MapRemoteRule {
        func given(_ key: String) -> String? {
            let value = (args[key] as? String)?.trimmingCharacters(in: .whitespaces)
            return value?.isEmpty == false ? value : nil
        }
        guard given("host") != nil || given("path") != nil else {
            throw Failure(description: "create_map_remote needs a host or a path")
        }
        let destination = MapRemoteRule.Destination(host: given("host"), path: given("path"))
        let matching = MatchingRule(pattern: args["pattern"] as? String ?? "*")
        return MapRemoteRule(matching: matching, destination: destination)
    }

    private static func reverseProxyRule(_ args: [String: Any]) throws -> ReverseProxyRule {
        guard let local = Int(args["local_port"] as? String ?? ""), PortRange.isValid(local) else {
            throw Failure(description: "local_port must be a number from 1 to 65535")
        }
        let remote = Int(args["remote_port"] as? String ?? "") ?? 443
        guard PortRange.isValid(remote) else {
            throw Failure(description: "remote_port must be a number from 1 to 65535")
        }
        return ReverseProxyRule(localPort: local, remoteHost: args["remote_host"] as? String ?? "", remotePort: remote)
    }

    private func definitions() -> [ToolDefinition] {
        let engine = engine, localAddresses = localAddresses
        func flow(_ args: [String: Any]) throws -> Flow {
            guard let sequence = Int(args["sequence"] as? String ?? ""),
                  let found = engine.store.all.first(where: { $0.sequence == sequence })
            else {
                throw Failure(description: "No request with that sequence number")
            }
            return found
        }
        func edit(_ change: @escaping (inout WatcherSettings) -> Void) async throws -> String {
            try await engine.updateSettings(change)
            return "OK"
        }
        func matching(_ args: [String: Any]) -> MatchingRule {
            MatchingRule(pattern: args["pattern"] as? String ?? "*")
        }

        return [
            ToolDefinition(name: "get_proxy_status", description: "Whether Watcher is running and on which port.", properties: [:], required: []) { _ in
                Self.status(of: engine, lan: localAddresses())
            },
            ToolDefinition(name: "get_flows", description: "List captured requests (newest last).", properties: ["filter": "Only URLs containing this text", "limit": "Maximum rows, default 50"], required: []) { args in
                let filter = args["filter"] as? String ?? ""
                let limit = max(0, Int(args["limit"] as? String ?? "") ?? 50)
                let rows = engine.store.all.filter { filter.isEmpty || $0.request.url.localizedCaseInsensitiveContains(filter) }.suffix(limit)
                return rows.map { "\($0.sequence)\t\($0.response.map { "\($0.status)" } ?? "-")\t\($0.request.method)\t\($0.request.url)" }.joined(separator: "\n")
            },
            ToolDefinition(name: "get_flow_detail", description: "Headers and body of one request and its response.", properties: ["sequence": "Request number from get_flows"], required: ["sequence"]) { args in
                let flow = try flow(args)
                let hide = engine.settings.value.mcpRedaction
                func text(_ headers: [Header], _ body: Data) -> String {
                    (hide ? Redaction.redact(headers) : headers).map { "\($0.name): \($0.value)" }.joined(separator: "\n") + "\n\n" + String(BodyPreview.text(body, contentType: headers.value(for: "content-type")).prefix(20000))
                }
                let response = flow.response.map { "HTTP \($0.status)\n" + text($0.headers, $0.body) } ?? "(no response)"
                return "\(flow.request.method) \(flow.request.url)\n" + text(flow.request.headers, flow.request.body) + "\n\n--- response ---\n" + response
            },
            ToolDefinition(name: "get_websocket_messages", description: "Messages of a WebSocket connection.", properties: ["sequence": "Request number"], required: ["sequence"]) { args in
                try flow(args).webSocketMessages.map {
                    "\($0.direction == .clientToServer ? "→" : "←") \($0.kind.rawValue) " + (String(data: $0.payload, encoding: .utf8) ?? "<\($0.payload.count) bytes>")
                }.joined(separator: "\n")
            },
            ToolDefinition(name: "export_flow_curl", description: "A cURL command that repeats a captured request.", properties: ["sequence": "Request number"], required: ["sequence"]) { args in
                let request = try flow(args).request
                return CodeGenerator.generate(engine.settings.value.mcpRedaction ? Redaction.redact(request) : request, as: .curl)
            },
            ToolDefinition(name: "clear_session", description: "Remove every captured request.", properties: [:], required: []) { _ in
                engine.store.clear(); return "OK"
            },
            ToolDefinition(name: "list_rules", description: "Every tool and its rules.", properties: [:], required: []) { _ in
                let s = engine.settings.value
                func line(_ name: String, _ set: RuleSet<some ToolRule>) -> String {
                    "\(name): \(set.isEnabled ? "on" : "off"), \(set.rules.count) rule(s)"
                }
                return [
                    line("block-list", s.blockList),
                    line("allow-list", s.allowList),
                    line("map-local", s.mapLocal),
                    line("map-remote", s.mapRemote),
                    line("breakpoint", s.breakpoints),
                    line("scripting", s.scripting),
                    line("dns-spoofing", s.dnsSpoofing),
                    line("reverse-proxy", s.reverseProxy),
                    "network-condition: \(s.throttle.isEnabled ? "on (\(s.throttle.profile.name))" : "off")",
                    "no-caching: \(s.noCaching ? "on" : "off")",
                ].joined(separator: "\n")
            },
            ToolDefinition(name: "get_ssl_proxying_list", description: "Hosts that are decrypted or excluded.", properties: [:], required: []) { _ in
                let s = engine.settings.value.sslProxying
                return "include: \(s.include.joined(separator: ", "))\nexclude: \(s.exclude.joined(separator: ", "))"
            },
            ToolDefinition(name: "get_certificate_status", description: "Location of the root certificate to trust.", properties: [:], required: []) { _ in
                engine.authority.certificateURL.path
            },
            ToolDefinition(name: "create_blacklist", description: "Block requests whose URL matches a pattern (* and ?).", properties: ["pattern": "URL pattern"], required: ["pattern"]) { args in
                try await edit { $0.blockList.isEnabled = true; $0.blockList.rules.append(BlockRule(matching: matching(args))) }
            },
            ToolDefinition(name: "create_allow_list", description: "Allow only requests matching a pattern.", properties: ["pattern": "URL pattern"], required: ["pattern"]) { args in
                try await edit { $0.allowList.isEnabled = true; $0.allowList.rules.append(AllowRule(matching: matching(args))) }
            },
            ToolDefinition(name: "create_map_local", description: "Answer matching requests from a local file.", properties: ["pattern": "URL pattern", "file_path": "Local file"], required: ["pattern", "file_path"]) { args in
                try await edit { $0.mapLocal.isEnabled = true; $0.mapLocal.rules.append(MapLocalRule(matching: matching(args), source: .file(args["file_path"] as? String ?? ""))) }
            },
            ToolDefinition(name: "create_map_remote", description: "Redirect matching requests to another host/path.", properties: ["pattern": "URL pattern", "host": "New host", "path": "New path"], required: ["pattern"]) { args in
                let rule = try Self.mapRemoteRule(args)
                return try await edit { $0.mapRemote.isEnabled = true; $0.mapRemote.rules.append(rule) }
            },
            ToolDefinition(name: "create_breakpoint", description: "Pause matching requests and responses for editing in the app.", properties: ["pattern": "URL pattern"], required: ["pattern"]) { args in
                try await edit { $0.breakpoints.isEnabled = true; $0.breakpoints.rules.append(BreakpointRule(matching: matching(args))) }
            },
            ToolDefinition(name: "create_dns_spoofing", description: "Send a host name to another address.", properties: ["host": "Host name", "address": "IP address or host"], required: ["host", "address"]) { args in
                try await edit { $0.dnsSpoofing.isEnabled = true; $0.dnsSpoofing.rules.append(DNSSpoofRule(host: args["host"] as? String ?? "", address: args["address"] as? String ?? "")) }
            },
            ToolDefinition(name: "create_network_condition", description: "Throttle the network with a preset (\(NetworkProfile.presets.map(\.name).joined(separator: ", "))) or a saved custom profile.", properties: ["preset": "Preset or saved profile name"], required: ["preset"]) { args in
                guard let preset = engine.settings.value.throttle.availableProfiles.first(where: { $0.name == args["preset"] as? String }) else { throw Failure(description: "Unknown preset") }
                return try await edit { $0.throttle.isEnabled = true; $0.throttle.profile = preset }
            },
            ToolDefinition(name: "create_reverse_proxy", description: "Listen on a local port and forward to a remote host.", properties: ["local_port": "Local port", "remote_host": "Remote host", "remote_port": "Remote port, default 443"], required: ["local_port", "remote_host"]) { args in
                let rule = try Self.reverseProxyRule(args)
                return try await edit { $0.reverseProxy.isEnabled = true; $0.reverseProxy.rules.append(rule) }
            },
            ToolDefinition(name: "create_scripting_rule", description: "Run JavaScript (onRequest/onResponse) on matching traffic.", properties: ["pattern": "URL pattern", "source": "JavaScript source"], required: ["pattern", "source"]) { args in
                try await edit { $0.scripting.isEnabled = true; $0.scripting.rules.append(ScriptRule(matching: matching(args), source: args["source"] as? String ?? "")) }
            },
            ToolDefinition(name: "create_compose_http", description: "Send an HTTP request through Watcher and return the response.", properties: ["method": "HTTP method", "url": "Absolute URL", "headers": "Lines of `Name: value`", "body": "Request body"], required: ["url"]) { args in
                guard let url = URLComponents(string: args["url"] as? String ?? ""), let host = url.host else { throw Failure(description: "url must be absolute") }
                let scheme = url.scheme ?? "https"
                let headers = (args["headers"] as? String ?? "").split(separator: "\n").compactMap { line -> Header? in
                    guard let colon = line.firstIndex(of: ":") else { return nil }
                    return Header(line[..<colon].trimmingCharacters(in: .whitespaces), line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces))
                }
                let request = RequestRecord(
                    method: (args["method"] as? String ?? "GET").uppercased(),
                    scheme: scheme,
                    host: host,
                    port: url.port ?? RequestRecord.defaultPort(for: scheme),
                    path: (url.percentEncodedPath.isEmpty ? "/" : url.percentEncodedPath) + (url.percentEncodedQuery.map { "?\($0)" } ?? ""),
                    headers: headers,
                    body: Data((args["body"] as? String ?? "").utf8)
                )
                let response = await engine.send(request)
                return "HTTP \(response.status)\n" + String(BodyPreview.text(response.body, contentType: response.headers.value(for: "content-type")).prefix(20000))
            },
        ]
    }

    // MARK: JSON-RPC plumbing

    private func describe(_ tool: ToolDefinition) -> [String: Any] {
        [
            "name": tool.name,
            "description": tool.description,
            "inputSchema": ["type": "object", "properties": tool.properties.mapValues { ["type": "string", "description": $0] }, "required": tool.required] as [String: Any],
        ]
    }

    private func content(_ text: String, isError: Bool) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "isError": isError]
    }

    private func response(id: Any, result: Any) -> String {
        encode(["jsonrpc": "2.0", "id": id, "result": result])
    }

    private func response(id: Any, error: (Int, String)) -> String {
        encode(["jsonrpc": "2.0", "id": id, "error": ["code": error.0, "message": error.1]])
    }

    private func encode(_ object: [String: Any]) -> String {
        String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data("{}".utf8), as: UTF8.self)
    }
}
