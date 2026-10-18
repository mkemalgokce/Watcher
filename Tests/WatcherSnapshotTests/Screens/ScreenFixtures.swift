import Foundation
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The fixed traffic and models every screen snapshot is built from, so references never depend on the clock or the machine.
enum Screen {
    static let started = Date(timeIntervalSince1970: 1_700_000_000)

    /// A 64×40 red PNG.
    static let redPNG = Data(base64Encoded: """
    iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAIAAADBrGu+AAAAWElEQVR4nO3PwQkAIBDAsJvLv/uPpEP4CEKhA6Rz9vq64YIGtKABLWhACxrQ\
    gga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALHrtwRezT21HipwAAAABJRU5ErkJggg==
    """)!

    @MainActor
    static func model(flows: [Flow] = [], selecting selected: Flow? = nil) throws -> AppModel {
        let model = try AppModel.test()
        model.onboardingDone = true
        model.engine.store.load(flows)
        model.list.syncFromStore()
        model.list.selection = selected?.id
        return model
    }

    @MainActor
    static func demo() throws -> AppModel {
        let model = try AppModel.test().showingDemoData(startedAt: started)
        model.onboardingDone = true
        return model
    }

    static func exchange(
        _ sequence: Int,
        _ method: String = "GET",
        _ url: String,
        status: Int? = 200,
        contentType: String = "application/json",
        requestBody: String = "",
        requestHeaders: [Header] = [],
        body: Data = Data(),
        duration: TimeInterval = 0.12,
        error: String? = nil
    ) -> Flow {
        var flow = Flow.fixture(
            sequence: sequence,
            request: .fixture(
                method: method, url: url, headers: requestHeaders + [Header("Accept", "*/*")],
                body: Data(requestBody.utf8)
            ),
            response: status.map { .fixture(
                status: $0, headers: [Header("Content-Type", contentType), Header("Server", "nginx")], body: body
            ) },
            duration: duration
        )
        flow.startedAt = started.addingTimeInterval(Double(sequence))
        flow.error = error
        return flow
    }

    static func json(_ text: String) -> Data {
        Data(text.utf8)
    }

    static let users = exchange(
        1, "POST", "https://api.example.com/v1/users?page=2",
        status: 201, requestBody: #"{"name":"Ada","role":"admin"}"#,
        requestHeaders: [Header("Content-Type", "application/json"), Header("Cookie", "theme=dark; lang=en")],
        body: json(#"{"id":7,"name":"Ada","role":"admin","active":true,"tags":["a","b"]}"#), duration: 0.184
    )

    static let image = exchange(
        2, "GET", "https://cdn.example.com/avatar.png", contentType: "image/png", body: redPNG, duration: 0.05
    )

    static let failed = exchange(
        4, "GET", "https://slow.example.com/report", status: nil, duration: 5,
        error: "The network connection was lost."
    )

    static let webSocket: Flow = {
        var flow = exchange(5, "GET", "wss://chat.example.com/socket", status: 101, contentType: "text/plain")
        flow.webSocketMessages = [
            WebSocketMessage(
                direction: .clientToServer, kind: .text, payload: json(#"{"type":"join","room":"general"}"#),
                date: started
            ),
            WebSocketMessage(
                direction: .serverToClient, kind: .text, payload: json(#"{"type":"joined","users":3}"#),
                date: started.addingTimeInterval(1)
            ),
            WebSocketMessage(
                direction: .serverToClient, kind: .ping, payload: Data(), date: started.addingTimeInterval(2)
            ),
        ]
        return flow
    }()

    static let embedded = exchange(
        6, "GET", "https://api.example.com/v1/profile",
        body: json(#"{"name":"Ada","avatar":"data:image/png;base64,\#(redPNG.base64EncodedString())"}"#)
    )

    static let exchanges = [users, image, failed, webSocket, embedded]
}

extension Screen {
    /// Every tool with a rule or two that reads like real use.
    static var toolSettings: WatcherSettings {
        var settings = WatcherSettings()
        let api = MatchingRule(pattern: "api.example.com/v1/*", methods: ["GET", "POST"])
        let assets = MatchingRule(pattern: "cdn.example.com/*")
        let login = MatchingRule(pattern: "api.example.com/v1/login")
        let trackers = MatchingRule(pattern: "*.tracker.net/*")
        settings.sslProxying = SSLProxyingSettings(include: ["*.example.com"], exclude: ["bank.example.com"])
        settings.blockList = ruleSet(BlockRule(name: "Trackers", matching: trackers))
        settings.allowList = ruleSet(AllowRule(name: "Only the API", matching: api))
        settings.mapLocal = ruleSet(MapLocalRule(matching: assets, source: .file("/Users/ada/mocks/app.js")))
        settings.mapRemote = ruleSet(MapRemoteRule(matching: api, destination: .init(host: "staging.example.com")))
        settings.breakpoints = ruleSet(BreakpointRule(matching: login))
        settings.scripting = ruleSet(ScriptRule(matching: api, source: "response.headers['X-Debug'] = '1'"))
        settings.dnsSpoofing = ruleSet(DNSSpoofRule(host: "api.example.com", address: "10.0.0.8"))
        settings.reverseProxy = ruleSet(ReverseProxyRule(localPort: 8080, remoteHost: "api.example.com"))
        settings.protobuf = ruleSet(ProtobufRule(matching: api, requestType: "example.User"))
        settings.previewers = ruleSet(PreviewerRule(matching: api, source: "return body.toUpperCase()"))
        settings.customCertificates = ruleSet(
            CustomCertificateRule(host: "mtls.example.com", role: .client, p12Path: "/Users/ada/client.p12")
        )
        settings.throttle = ThrottleSettings(
            isEnabled: true, profile: NetworkProfile.presets[1], host: "api.example.com"
        )
        settings.externalProxy = ExternalProxySettings(
            isEnabled: true, kind: .socks, host: "proxy.corp.example.com", port: 1080
        )
        return settings
    }

    private static func ruleSet<Rule: ToolRule>(_ rule: Rule) -> RuleSet<Rule> {
        RuleSet(isEnabled: true, rules: [rule])
    }
}
