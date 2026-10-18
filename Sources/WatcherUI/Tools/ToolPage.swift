/// One page of the Tools window: its name, icon, what it does and which group it sits in.
enum ToolPage: String, CaseIterable, Identifiable {
    case sslProxying = "SSL Proxying"
    case breakpoint = "Breakpoints"
    case mapLocal = "Map Local"
    case mapRemote = "Map Remote"
    case scripting = "Scripting"
    case block = "Block List"
    case allow = "Allow List"
    case throttling = "Throttling"
    case dns = "DNS Spoofing"
    case reverse = "Reverse Proxy"
    case externalProxy = "External Proxy"
    case protobuf = "Protobuf"
    case previewers = "Previewers"
    case certificates = "Certificates"
    var id: Self {
        self
    }

    var icon: String {
        switch self {
        case .sslProxying: "lock.open"
        case .block: "nosign"
        case .allow: "checkmark.shield"
        case .mapLocal: "doc.on.doc"
        case .mapRemote: "arrow.triangle.swap"
        case .breakpoint: "pause.circle"
        case .scripting: "curlybraces"
        case .throttling: "tortoise"
        case .dns: "server.rack"
        case .reverse: "arrow.uturn.left"
        case .externalProxy: "point.3.connected.trianglepath.dotted"
        case .protobuf: "shippingbox"
        case .previewers: "eye"
        case .certificates: "lock.doc"
        }
    }

    /// What the tool does and when to reach for it, shown at the top of its page.
    var explanation: String {
        switch self {
        case .sslProxying: """
            Which HTTPS hosts Watcher decrypts. Other hosts pass through as encrypted tunnels: you \
            see the host name, not the content. The client must trust Watcher's certificate (⇧⌘D).
            """
        case .breakpoint: """
            Pauses matching requests or responses so you can change them before they continue. \
            Paused traffic opens in Breakpoints (⌘B).
            """
        case .mapLocal: """
            Answers matching requests with a file from your disk instead of calling the server. Edit \
            a JSON file to try UI states without touching the backend.
            """
        case .mapRemote: """
            Sends matching requests somewhere else, for example production to staging. Empty fields \
            keep the original value.
            """
        case .scripting: """
            Runs JavaScript on matching traffic. onRequest(context, url, request) and \
            onResponse(context, url, request, response) return the changed message.
            """
        case .block: """
            Answers matching requests with 403 instead of sending them. Shows how an app copes when \
            a service is down.
            """
        case .allow: "Only matching requests go through; everything else is blocked. Useful to focus on one API."
        case .throttling: "Simulates a slow or lossy network for all traffic, or for one host."
        case .dns: """
            Resolves a host name to the address you choose, like an /etc/hosts entry that only \
            applies to traffic through Watcher.
            """
        case .reverse: """
            Listens on a local port and forwards to a server. Point a client at localhost:port to \
            capture it without any proxy settings.
            """
        case .externalProxy: "Sends Watcher's outgoing traffic through another proxy, such as a corporate proxy."
        case .protobuf: "Decodes protobuf bodies with your schemas so they show as named fields instead of numbers."
        case .previewers: "Adds your own inspector tab: JavaScript that turns a request into text."
        case .certificates: """
            Uses your own certificate for a host, or presents a client certificate to the server \
            (mutual TLS).
            """
        }
    }

    static let groups: [(String, [ToolPage])] = [
        ("Inspect", [.sslProxying, .breakpoint, .protobuf, .previewers]),
        ("Change traffic", [.mapLocal, .mapRemote, .scripting, .block, .allow]),
        ("Network", [.throttling, .dns, .reverse, .externalProxy, .certificates]),
    ]
}
