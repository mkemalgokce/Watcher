import SwiftUI
import WatcherCore

extension AppModel {
    /// A handful of realistic-looking requests covering the list's states.
    func loadDemoData() {
        func flow(_ n: Int, _ method: String, _ host: String, _ path: String, status: Int?, type: String = "application/json", body: String = "", ms: Double = 0.12, tools: [String] = []) -> Flow {
            var flow = Flow(sequence: n, request: RequestRecord(
                method: method,
                scheme: "https",
                host: host,
                port: 443,
                path: path,
                headers: [Header("Accept", "application/json"), Header("User-Agent", "Demo/1.0")],
                clientApp: ["Google Chrome", "curl", "Slack", "Safari", "Xcode"][(n - 1) % 5]
            ))
            if let status {
                flow.response = ResponseRecord(status: status, headers: [Header("Content-Type", type), Header("Server", "nginx")], body: Data(body.utf8))
                flow.state = .completed
            } else {
                flow.state = .failed
            }
            flow.duration = ms; flow.appliedTools = tools
            return flow
        }
        engine.store.load([
            flow(1, "GET", "api.example.com", "/v1/users?page=1", status: 200, body: #"{"users":[{"id":1,"name":"Ada"},{"id":2,"name":"Linus"}],"next":null}"#, ms: 0.184),
            flow(2, "POST", "api.example.com", "/v1/login", status: 401, body: #"{"error":"invalid_credentials"}"#, ms: 0.091),
            flow(3, "GET", "cdn.example.com", "/app.js", status: 200, type: "application/javascript", body: "console.log('hi')", ms: 0.03, tools: ["Map Local"]),
            flow(4, "GET", "ads.tracker.net", "/pixel.gif", status: 403, type: "text/plain", body: "Blocked by Watcher", ms: 0, tools: ["Block List"]),
            flow(5, "GET", "slow.example.com", "/report", status: nil, ms: 5.0),
        ])
    }
}

#if DEBUG
    extension AppModel {
        /// A model filled with demo traffic for Xcode previews.
        @MainActor static func preview() -> AppModel {
            UserDefaults.standard.set("Preview", forKey: "body.mode") // previews share defaults; start from the app's default view
            let model = AppModel(listening: false)
            model.loadDemoData()
            model.syncFromStore()
            model.selection = model.flows.first?.id
            return model
        }
    }

    #Preview("Main window", traits: .fixedLayout(width: 1320, height: 780)) {
        ContentView().environment(AppModel.preview())
    }

    #Preview("Device setup") { DeviceSetupView().environment(AppModel.preview()) }
    #Preview("Settings") { SettingsView().environment(AppModel.preview()) }
    #Preview("Compose") { ComposeView().environment(AppModel.preview()) }
    #Preview("Tools") { ToolsView().environment(AppModel.preview()) }
    #Preview("Breakpoints") { BreakpointsView().environment(AppModel.preview()) }
    #Preview("Android setup") { DeviceSetupView(target: .android).environment(AppModel.preview()) }
#endif

#if DEBUG
    #Preview("Large JSON", traits: .fixedLayout(width: 1320, height: 780)) {
        UserDefaults.standard.set("Preview", forKey: "body.mode")
        let model = AppModel(listening: false)
        let item = #"{"id":12345,"name":"Ada Lovelace","tags":["a","b",null,true],"score":-1.5e3,"avatar":"https://example.com/a.png"},"#
        let body = "[" + String(repeating: item, count: 300_000) + #"{"end":true}]"# // ~33 MB
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/export", clientApp: "curl"))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json")], body: Data(body.utf8))
        flow.state = .completed; flow.duration = 1.2
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = model.flows.first?.id
        return ContentView().environment(model)
    }

    #Preview("Form data", traits: .fixedLayout(width: 1320, height: 780)) {
        UserDefaults.standard.set("Preview", forKey: "body.mode")
        let model = AppModel(listening: false)
        // A 2×2 red PNG, uploaded next to an ordinary field.
        let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAIAAADBrGu+AAAAWElEQVR4nO3PwQkAIBDAsJvLv/uPpEP4CEKhA6Rz9vq64YIGtKABLWhACxrQgga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALHrtwRezT21HipwAAAABJRU5ErkJggg==")!
        var body = Data("--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nHoliday photo\r\n--B\r\nContent-Disposition: form-data; name=\"photo\"; filename=\"red.png\"\r\nContent-Type: image/png\r\n\r\n".utf8)
        body.append(png); body.append(Data("\r\n--B--\r\n".utf8))
        var flow = Flow(sequence: 1, request: RequestRecord(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            path: "/v1/upload?album=summer&public=true",
            headers: [Header("Content-Type", "multipart/form-data; boundary=B")],
            body: body,
            clientApp: "Safari"
        ))
        flow.response = ResponseRecord(status: 201, headers: [Header("Content-Type", "application/json")], body: Data(#"{"id":"p_42","url":"https://cdn.example.com/p_42.png"}"#.utf8))
        flow.state = .completed; flow.duration = 0.31
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = model.flows.first?.id
        return ContentView().environment(model)
    }

    #Preview("Breakpoints paused") {
        let model = AppModel.preview()
        model.hits = [
            .init(phase: .request, request: RequestRecord(
                method: "POST",
                scheme: "https",
                host: "api.example.com",
                port: 443,
                path: "/v1/login",
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"user":"ada","password":"secret"}"#.utf8)
            )),
            .init(
                phase: .response,
                request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/me"),
                response: ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json")], body: Data(#"{"id":42,"plan":"free"}"#.utf8))
            ),
        ]
        return BreakpointsView().environment(model)
    }

    #Preview("Insights", traits: .fixedLayout(width: 1320, height: 900)) {
        UserDefaults.standard.set("Preview", forKey: "body.mode")
        let model = AppModel(listening: false)
        let png = "iVBORw0KGgoAAAANSUhEUgAAADAAAAAwCAIAAADYYG7QAAAAQUlEQVR4nO3OMQ0AIBAAsZ/RjW9wwTE0qYDO2ucrkw+EhISE6oGQkJBQPRASEhKqB0JCQkL1QEhISKgeCAkJPXYBFEP1xJNEZhsAAAAASUVORK5CYII="
        func part(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        }
        let jwt = part(#"{"alg":"HS256","typ":"JWT"}"#) + "." + part(#"{"sub":"42","name":"Ada","exp":4102444800}"#) + ".sig"
        var flow = Flow(sequence: 1, request: RequestRecord(
            method: "GET",
            scheme: "https",
            host: "api.example.com",
            port: 443,
            path: "/v1/profile",
            headers: [Header("Authorization", "Bearer \(jwt)"), Header("Cookie", "theme=dark; lang=tr")]
        ))
        flow.response = ResponseRecord(
            status: 200,
            headers: [Header("Content-Type", "application/json"), Header("Set-Cookie", "sid=abc123; Path=/")],
            body: Data(#"{"name":"Ada","avatar":"data:image/png;base64,\#(png)"}"#.utf8)
        )
        flow.state = .completed
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = model.flows.first?.id
        return ContentView().environment(model)
    }

    #Preview("Converter") { ConverterView().environment(AppModel.preview()) }

    #Preview("Notices", traits: .fixedLayout(width: 1100, height: 500)) {
        let model = AppModel.preview()
        model.notices.notify("Cannot start the proxy: port 9090 is in use. Pick a different port in Settings.", .error)
        return ContentView().environment(model)
    }

    #Preview("Welcome") { WelcomeView().environment(AppModel.preview()) }
#endif

#if DEBUG
    #Preview("HTML response", traits: .fixedLayout(width: 1320, height: 780)) {
        ContentView().environment(singleResponse("text/html; charset=utf-8", Data("""
        <html><body style="font-family:-apple-system;padding:24px"><h1 style="color:#0a84ff">Welcome back, Ada</h1>
        <p>Your <b>3 orders</b> are on their way.</p><ul><li>Keyboard</li><li>Monitor</li><li>Cable</li></ul>
        <script>document.body.innerHTML = 'SCRIPT RAN'</script><img src="https://tracker.example.com/pixel.gif"></body></html>
        """.utf8), path: "/account"))
    }

    #Preview("PDF response", traits: .fixedLayout(width: 1320, height: 780)) {
        ContentView().environment(singleResponse("application/pdf", samplePDF(), path: "/invoice.pdf"))
    }

    #Preview("Main window, light", traits: .fixedLayout(width: 1320, height: 780)) {
        ContentView().environment(AppModel.preview()).preferredColorScheme(.light)
    }
#endif

#if DEBUG
    #Preview("Main window, wide", traits: .fixedLayout(width: 1800, height: 820)) {
        ContentView().environment(AppModel.preview())
    }

    #Preview("First run", traits: .fixedLayout(width: 1320, height: 780)) {
        ContentView().environment(AppModel(listening: false))
    }

    #Preview("Help") { HelpView() }
#endif
