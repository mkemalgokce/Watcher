import AppKit
import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// Every screen lays out in an off-screen window without hanging or crashing, at a narrow and a wide size.
/// `WATCHER_SCREENS=<dir> swift test --filter ScreensTests` also writes what was drawn, to look at the layout without opening the app.
@MainActor
final class ScreensTests: XCTestCase {
    private func layOut(_ view: some View, width: CGFloat, height: CGFloat, name: String, settle: TimeInterval = 0.3) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: height), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // The references are dark; pin it so the result does not depend on the Mac's (or a CI runner's) appearance.
        window.appearance = NSAppearance(named: .darkAqua)
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        window.contentView = host
        window.layoutIfNeeded()
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settle))
        XCTAssertFalse(host.subviews.isEmpty, "\(name) drew nothing")
        let png = SnapshotMode.render(layerOf: host)
        if let directory = ProcessInfo.processInfo.environment["WATCHER_SCREENS"] {
            try? png?.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
        if let png {
            assertSnapshot(png, named: name)
        }
        window.close()
    }

    /// Reference images live in __Snapshots__; a missing one is recorded, and `WATCHER_RECORD=1` re-records them all after an intended change.
    /// Small differences (favicons fetched from the network, font smoothing) are tolerated; a moved or missing pane is not.
    private func assertSnapshot(_ png: Data, named name: String, file: StaticString = #filePath, line: UInt = #line) {
        let directory = URL(fileURLWithPath: "\(file)").deletingLastPathComponent().appendingPathComponent("__Snapshots__")
        let reference = directory.appendingPathComponent("\(name).png")
        guard ProcessInfo.processInfo.environment["WATCHER_RECORD"] == nil, let expected = try? Data(contentsOf: reference) else {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? png.write(to: reference)
            return
        }
        guard let difference = Self.difference(png, expected) else { return XCTFail("\(name): size changed", file: file, line: line) }
        if difference > 0.02 {
            let failed = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-actual.png")
            try? png.write(to: failed)
            XCTFail("\(name) differs from its reference in \(String(format: "%.1f", difference * 100))% of pixels; see \(failed.path)", file: file, line: line)
        }
    }

    /// Share of pixels whose colour moved by more than a little; nil when the images are not the same size.
    static func difference(_ a: Data, _ b: Data) -> Double? {
        guard let x = rgba(a), let y = rgba(b), x.width == y.width, x.height == y.height else { return nil }
        var changed = 0
        for pixel in stride(from: 0, to: x.bytes.count, by: 4) {
            let delta = (0 ..< 3).reduce(0) { $0 + abs(Int(x.bytes[pixel + $1]) - Int(y.bytes[pixel + $1])) }
            if delta > 24 {
                changed += 1
            }
        }
        return Double(changed) / Double(x.width * x.height)
    }

    private static func rgba(_ png: Data) -> (bytes: [UInt8], width: Int, height: Int)? {
        guard let image = NSBitmapImageRep(data: png)?.cgImage else { return nil }
        let (width, height) = (image.width, image.height)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? (bytes, width, height) : nil
    }

    func testSnapshotDifferenceIgnoresNothingAndCatchesChanges() {
        func image(_ color: CGColor) -> Data {
            let context = CGContext(
                data: nil,
                width: 8,
                height: 8,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )!
            context.setFillColor(color); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
        }
        let red = CGColor(red: 1, green: 0, blue: 0, alpha: 1), blue = CGColor(red: 0, green: 0, blue: 1, alpha: 1)
        XCTAssertEqual(Self.difference(image(red), image(red)), 0)
        XCTAssertEqual(Self.difference(image(red), image(blue)), 1)
    }

    /// The states a user has to be told about: filters hiding everything, a proxy that failed to start, a file being opened, devices being scanned.
    func testStateScreens() {
        let filtered = AppModel.preview()
        filtered.query.text = "nothing-matches-this"
        layOut(FlowListView().environment(filtered), width: 760, height: 480, name: "list-no-matches")

        let failed = AppModel(listening: false)
        failed.proxyError = "Cannot start the proxy: address already in use. Another app may be using port 9090; pick a different port in Settings."
        layOut(FlowListView().environment(failed), width: 760, height: 560, name: "list-proxy-error")

        let busy = AppModel.preview()
        busy.busyMessage = "Opening session.har…"
        layOut(StatusBar().environment(busy), width: 1100, height: 28, name: "statusbar-busy")

        let breakpoints = AppModel.preview()
        breakpoints.settings.breakpoints = RuleSet(isEnabled: true, rules: [
            BreakpointRule(name: "Login", matching: MatchingRule(pattern: "api.example.com/v1/login")),
            BreakpointRule(name: "", isEnabled: false, matching: MatchingRule(pattern: "*/v1/users*")),
        ])
        layOut(BreakpointsView().environment(breakpoints), width: 900, height: 560, name: "breakpoints-rules")

        let filtering = AppModel.preview()
        filtering.query.statusClasses = [4]; filtering.query.methods = ["POST"]
        layOut(FlowListView().environment(filtering), width: 900, height: 300, name: "list-filtered")

        let scanning = AppModel(listening: false)
        scanning.devices.isScanning = true
        layOut(DeviceSetupView(target: .simulator).environment(scanning), width: 720, height: 520, name: "devices-scanning")
    }

    func testMainWindowAtEverySize() {
        for (name, width, height) in [("main-narrow", 1040.0, 600.0), ("main", 1320.0, 780.0), ("main-wide", 1800.0, 900.0)] {
            layOut(ContentView().environment(AppModel.preview()), width: width, height: height, name: name)
        }
        layOut(ContentView().environment(AppModel(listening: false)), width: 1320, height: 780, name: "main-first-run")
    }

    func testInspectorAtEveryWidth() {
        for (suffix, width) in [("narrow", 420.0), ("wide", 900.0)] {
            layOut(FlowDetailView().environment(AppModel.preview()), width: width, height: 640, name: "inspector-\(suffix)")
        }
        // A WebSocket exchange gets a Messages section in the response panel instead of its own tab.
        let model = AppModel(listening: false)
        var socket = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "wss", host: "chat.example.com", port: 443, path: "/socket"))
        socket.response = ResponseRecord(status: 101, headers: [], body: Data()); socket.state = .completed
        socket.webSocketMessages = [
            WebSocketMessage(direction: .clientToServer, kind: .text, payload: Data(#"{"op":"hello"}"#.utf8)),
            WebSocketMessage(direction: .serverToClient, kind: .text, payload: Data(#"{"op":"welcome"}"#.utf8)),
        ]
        model.engine.store.load([socket]); model.syncFromStore(); model.selection = model.flows[0].id
        UserDefaults.standard.set("Messages", forKey: "panel.response.section")
        layOut(FlowDetailView().environment(model), width: 900, height: 500, name: "inspector-websocket")
        UserDefaults.standard.set("Body", forKey: "panel.response.section")
    }

    /// Compare with a real base (and without base or selection), plus the JWT button in the inspector header.
    func testCompareWindowAndJWT() {
        let model = AppModel.preview()
        var changed = Flow(sequence: 6, request: model.flows[0].request)
        changed.state = .completed; changed.duration = 0.2
        changed.response = model.flows[0].response
        changed.response?.body = Data(#"{"users":[{"id":1,"name":"Ada"},{"id":3,"name":"Grace"}],"next":"/v1/users?page=2"}"#.utf8)
        model.engine.store.load(model.flows + [changed]); model.syncFromStore()
        model.diffBase = model.flows[0]
        model.selection = model.flows[5].id
        layOut(CompareWindow().environment(model), width: 900, height: 640, name: "compare-content", settle: 1.5)
        model.diffBase = nil
        layOut(CompareWindow().environment(model), width: 900, height: 640, name: "compare-no-base")
        // A request carrying a JWT shows the decode button in the header.
        let header = #"{"alg":"HS256"}"#, payload = #"{"sub":"42","exp":4102444800}"#
        func part(_ s: String) -> String {
            Data(s.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        }
        var withToken = model.flows[0]
        withToken.request.headers.append(Header("Authorization", "Bearer \(part(header)).\(part(payload)).sig"))
        model.engine.store.load([withToken]); model.syncFromStore(); model.selection = model.flows[0].id
        layOut(FlowDetailView().environment(model), width: 900, height: 400, name: "inspector-jwt")
    }

    /// Traffic arriving while the sidebar is on screen leaves the selection on All Requests. (Once seen jumping to
    /// Starred in the running app; that could not be reproduced here, so this checks the behaviour, not that cause.)
    func testSidebarKeepsItsSelectionWhenTrafficArrives() {
        let model = AppModel(listening: false)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 260, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SidebarView().environment(model).frame(width: 260, height: 600))
        window.orderFront(nil) // the outline view only shifts its selection while it is really on screen
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        model.observeEngine()
        model.loadDemoData() // through store events, as live traffic arrives
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(model.sidebar, .all)
        XCTAssertEqual(model.visibleFlows.count, 5)
        window.close()
    }

    /// Long header values wrap inside the panel; the copy button at the end of each row stays visible.
    func testHeadersTableFitsThePanel() {
        let model = AppModel(listening: false)
        var flow = Flow(sequence: 1, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/me"))
        flow.response = ResponseRecord(status: 200, headers: [
            Header("Content-Type", "application/json; charset=utf-8"),
            Header("Content-Security-Policy", "default-src 'self'; script-src 'self' https://cdn.example.com https://analytics.example.com; img-src * data: blob:; frame-ancestors 'none'"),
            Header("Set-Cookie", "session=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiI0MiJ9.c2lnbmF0dXJlLWZvci10ZXN0cy1vbmx5; Path=/; HttpOnly; Secure; SameSite=Lax"),
            Header("X-Request-Id", "7f3c2a10-9b1e-4c55-8d2f-0a6b1c9e4d77"),
        ], body: Data("{}".utf8))
        flow.state = .completed; flow.duration = 0.2
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = flow.id
        UserDefaults.standard.set("Headers", forKey: "panel.response.section")
        defer { UserDefaults.standard.set("Body", forKey: "panel.response.section") }
        model.exchangeSide = .response
        layOut(FlowDetailView().environment(model), width: 420, height: 640, name: "inspector-headers-narrow")
        layOut(FlowDetailView().environment(model), width: 900, height: 640, name: "inspector-headers-wide")
    }

    /// A JSON response carrying a Base64 image: the Decoded section shows it with save, open and copy.
    func testDecodedSectionAndEditBanner() {
        let model = AppModel(listening: false)
        let png = "iVBORw0KGgoAAAANSUhEUgAAAEAAAAAoCAIAAADBrGu+AAAAWElEQVR4nO3PwQkAIBDAsJvLv/uPpEP4CEKhA6Rz9vq64YIGtKABLWhACxrQgga0oAEtaEALGtCCBrSgAS1oQAsa0IIGtKABLWhACxrQgga0oAEtaEALHrtwRezT21HipwAAAABJRU5ErkJggg=="
        var flow = Flow(sequence: 7, request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/profile"))
        flow.response = ResponseRecord(status: 200, headers: [Header("Content-Type", "application/json")], body: Data(#"{"name":"Ada","avatar":"\#(png)"}"#.utf8))
        flow.state = .completed; flow.duration = 0.12
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = model.flows[0].id
        UserDefaults.standard.set("Decoded", forKey: "panel.response.section")
        defer { UserDefaults.standard.set("Body", forKey: "panel.response.section") }
        layOut(FlowDetailView().environment(model), width: 900, height: 640, name: "inspector-decoded", settle: 0.8)

        model.editAndRepeat(model.flows[0])
        layOut(ComposeView().environment(model), width: 900, height: 600, name: "compose-edit-and-repeat")
    }

    func testNarrowInspectorShowsEitherSide() {
        for side in MessageSide.allCases {
            let model = AppModel.preview()
            model.exchangeSide = side
            layOut(FlowDetailView().environment(model), width: 420, height: 640, name: "inspector-\(side.rawValue)")
        }
    }

    func testEmptyResponseBody() {
        let model = AppModel(listening: false)
        var flow = Flow(sequence: 1, request: RequestRecord(method: "DELETE", scheme: "https", host: "api.example.com", port: 443, path: "/v1/items/7"))
        flow.response = ResponseRecord(status: 204, headers: [], body: Data())
        flow.state = .completed; flow.duration = 0.05
        model.engine.store.load([flow]); model.syncFromStore(); model.selection = flow.id
        layOut(FlowDetailView().environment(model), width: 900, height: 600, name: "inspector-empty-response")
    }

    func testToolsPages() {
        for tool in ToolsView.Tool.allCases {
            let model = AppModel(listening: false)
            model.toolsSelection = tool
            layOut(ToolsView().environment(model), width: 920, height: 620, name: "tools-\(tool.rawValue)")
        }
        let model = AppModel(listening: false)
        model.settings.mapLocal = RuleSet(isEnabled: false, rules: [MapLocalRule(name: "Users", matching: MatchingRule(pattern: "*/users"), source: .file("/tmp/u.json"))])
        model.toolsSelection = .mapLocal
        layOut(ToolsView().environment(model), width: 760, height: 520, name: "tools-with-rules-narrow")

        let invalid = AppModel(listening: false)
        invalid.settings.dnsSpoofing = RuleSet(isEnabled: true, rules: [DNSSpoofRule(host: "https://api.example.com", address: "not-an-ip")])
        invalid.toolsSelection = .dns
        layOut(ToolsView().environment(invalid), width: 920, height: 620, name: "tools-rule-problems")
    }

    func testSheets() {
        let paused = AppModel.preview()
        paused.hits = [
            .init(phase: .request, request: RequestRecord(
                method: "POST",
                scheme: "https",
                host: "api.example.com",
                port: 443,
                path: "/v1/login",
                headers: [Header("Content-Type", "application/json")],
                body: Data(#"{"user":"ada"}"#.utf8)
            )),
            .init(
                phase: .response,
                request: RequestRecord(method: "GET", scheme: "https", host: "api.example.com", port: 443, path: "/v1/me"),
                response: ResponseRecord(status: 204, headers: [], body: Data())
            ),
        ]
        let screens: [(String, AnyView, CGFloat, CGFloat)] = [
            ("breakpoints-empty", AnyView(BreakpointsView().environment(AppModel.preview())), 820, 540),
            ("breakpoints-paused", AnyView(BreakpointsView().environment(paused)), 820, 540),
            ("compose", AnyView(ComposeView().environment(AppModel.preview())), 820, 600),
            ("devices", AnyView(DeviceSetupView().environment(AppModel.preview())), 720, 560),
            ("converter", AnyView(ConverterView().environment(AppModel.preview())), 620, 480),
            ("welcome", AnyView(WelcomeView().environment(AppModel.preview())), 580, 560),
            ("about", AnyView(AboutView().environment(AppModel.preview())), 480, 660),
            ("help", AnyView(HelpView()), 640, 560),
            ("settings", AnyView(SettingsView().environment(AppModel.preview())), 520, 470),
        ]
        for (name, view, width, height) in screens {
            layOut(view, width: width, height: height, name: name)
        }
    }

    /// MenuBarExtra(isInserted:) writes its binding back on every update; bound to @AppStorage that loops and froze the app at launch.
    func testMenuBarItemHasNoInsertedBinding() throws {
        let app = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/Watcher/WatcherApp.swift").standardized,
            encoding: .utf8
        )
        XCTAssertTrue(app.contains("MenuBarExtra"))
        XCTAssertFalse(app.contains("isInserted:"))
    }

    /// Two menu items on one key combination means one of them silently never fires.
    func testMenuShortcutsAreUnique() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/WatcherUI/WatcherCommands.swift").standardized,
            encoding: .utf8
        )
        let pattern = try NSRegularExpression(pattern: #"\.keyboardShortcut\(("[^"]*"|\.\w+)(?:, modifiers: \[?([^)\]]*)\]?)?\)"#)
        var seen: [String: Int] = [:]
        for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let key = try String(source[XCTUnwrap(Range(match.range(at: 1), in: source))]).lowercased()
            let modifiers = try match.range(at: 2).location == NSNotFound ? ".command"
                : String(source[XCTUnwrap(Range(match.range(at: 2), in: source))]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.sorted().joined(separator: ",")
            seen["\(modifiers)+\(key)", default: 0] += 1
        }
        XCTAssertGreaterThan(seen.count, 30)
        XCTAssertEqual(seen.filter { $0.value > 1 }.keys.sorted(), [], "these key combinations are used twice")
    }

    /// The Help page lists every menu shortcut, so the list cannot silently fall behind the menus.
    func testHelpListsEveryMenuShortcut() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("../../Sources/WatcherUI/WatcherCommands.swift").standardized,
            encoding: .utf8
        )
        let listed = Set(Shortcut.groups.flatMap(\.items).map(\.keys))
        let pattern = try NSRegularExpression(pattern: #"\.keyboardShortcut\("(.)"(?:, modifiers: \[?([^)\]]*)\]?)?\)"#)
        var missing: [String] = []
        let matches = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
        XCTAssertGreaterThan(matches.count, 30, "the pattern no longer finds the menu shortcuts")
        for match in matches {
            let key = try String(source[XCTUnwrap(Range(match.range(at: 1), in: source))]).uppercased()
            let modifiers = try match.range(at: 2).location == NSNotFound ? ".command" : String(source[XCTUnwrap(Range(match.range(at: 2), in: source))])
            var symbol = ""
            if modifiers.contains(".control") {
                symbol += "⌃"
            }
            if modifiers.contains(".option") {
                symbol += "⌥"
            }
            if modifiers.contains(".shift") {
                symbol += "⇧"
            }
            symbol += "⌘" + (key == "\\" ? "\\" : key)
            // Ranges such as "⌘1 – ⌘4" cover the numbered items.
            let covered = listed.contains(symbol) || listed.contains { $0.contains("–") && $0.hasPrefix(String(symbol.dropLast())) && key.allSatisfy(\.isNumber) }
            if !covered {
                missing.append(symbol)
            }
        }
        XCTAssertEqual(missing, [], "Add these to Shortcut.groups in HelpView.swift")
    }
}
