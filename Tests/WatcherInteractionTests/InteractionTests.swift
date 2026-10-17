import AppKit
import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// Flows driven the way a user drives them: the screen is shown in a real window and its controls are pressed through
/// accessibility (what VoiceOver and UI automation use), then the outcome is read from the model.
@MainActor
final class InteractionTests: XCTestCase {
    private var window: NSWindow?

    /// xctest is not launched as an app, so it does not answer accessibility requests until it becomes one.
    override func setUp() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSApp.finishLaunching()
        show(Text("Accessibility check"), width: 200, height: 100)
        defer { window?.close(); window = nil }
        try requireAccessibility()
    }

    override func tearDown() async throws {
        window?.close()
        window = nil
    }

    @discardableResult
    func show(_ view: some View, width: CGFloat = 1000, height: CGFloat = 640) -> NSView {
        // The same kind of window the app opens, so the toolbar gets the same room and layout (the centre item included).
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: view.frame(width: width, height: height))
        window.contentView = host
        window.orderFront(nil)
        self.window = window
        settle()
        return host
    }

    /// Stops the test with a clear reason when the system accessibility service does not hand out real windows (it has
    /// been seen to answer with the application element in a loop), instead of reporting every control as missing.
    private func requireAccessibility() throws {
        guard AXIsProcessTrusted() else { throw XCTSkip("Grant Accessibility to the app running the tests (System Settings ▸ Privacy & Security ▸ Accessibility).") }
        let app = AXUIElementCreateApplication(getpid())
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        var role: CFTypeRef?
        if let first = (windows as? [AXUIElement])?.first {
            AXUIElementCopyAttributeValue(first, kAXRoleAttribute as CFString, &role)
        }
        guard role as? String == "AXWindow" else {
            throw XCTSkip("The accessibility service returned \(role as? String ?? "no window") instead of the test window; restart Terminal (or run the tests from Xcode) and try again.")
        }
    }

    func settle(_ seconds: TimeInterval = 0.4) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }

    /// Every element in this test's window whose accessibility title or description is `label`, the same way
    /// UI automation sees them.
    func elements(_ label: String) -> [AXUIElement] {
        let windowNumber = window?.windowNumber ?? 0
        return AX.find(label, inWindow: windowNumber)
    }

    @discardableResult
    func press(_ label: String, file: StaticString = #filePath, line: UInt = #line) -> Bool {
        // Only something that can be pressed: a label's text matches too, but pressing it does nothing.
        let pressable = elements(label).first { element in
            var actions: CFArray?
            AXUIElementCopyActionNames(element, &actions)
            return (actions as? [String])?.contains(kAXPressAction as String) == true
        }
        guard let element = pressable else { XCTFail("no control labelled “\(label)”", file: file, line: line); return false }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        settle()
        XCTAssertEqual(result, .success, "“\(label)” did not respond to a press", file: file, line: line)
        return result == .success
    }

    // MARK: Toolbar

    func waitUntil(_ condition: () -> Bool, timeout: TimeInterval = 5) {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end {
            settle(0.1)
        }
    }

    /// Nothing is captured until Record; Record starts the proxy and Pause stops it, with the status bar following along.
    /// A free port is picked, and test settings never turn on the system proxy, so this cannot clash with a running Watcher
    /// or change the Mac's network.
    func testRecordStartsAndPauseStopsTheProxy() {
        let model = AppModel(listening: false)
        model.onboardingDone = true
        model.settings.port = PortFinder.firstAvailable(from: 20000) ?? 29999
        try? model.engine.settings.replace(with: model.settings)
        show(ContentView().environment(model), width: 1320, height: 780)

        settle(1)
        XCTAssertFalse(model.isRunning, "the proxy waits for Record")

        press("Record")
        waitUntil { model.isRunning && !model.isSwitchingProxy }
        XCTAssertTrue(model.isRunning)
        XCTAssertEqual(model.notice?.kind, .success)
        settle()
        let address = "127.0.0.1:\(model.engine.boundPort ?? 0)"
        XCTAssertTrue(model.statusLine.hasPrefix("Recording on \(address)"), "the status bar shows the address")

        press("Pause")
        waitUntil { !model.isRunning && !model.isSwitchingProxy }
        XCTAssertFalse(model.isRunning, "pausing stops the proxy")
        XCTAssertEqual(model.notice?.message, "Recording paused; the proxy is off")
        XCTAssertTrue(model.statusLine.hasPrefix("Not recording"))
    }

    func testToolbarOpensTheScreens() {
        let model = AppModel.preview()
        model.onboardingDone = true
        show(ContentView().environment(model), width: 1320, height: 780)
        for (label, sheet) in [("Compose", AppModel.Sheet.compose), ("Breakpoints", .breakpoints), ("Tools", .tools)] {
            model.sheet = nil; settle(0.3)
            press(label)
            XCTAssertEqual(model.sheet, sheet, label)
        }
        model.sheet = nil; settle(0.3)
        XCTAssertFalse(elements("More").isEmpty, "Start/Stop, converter, devices and shortcuts sit in the More menu")
    }

    // MARK: Filter bar

    func testTokensFilterTheListAndTheSummaryClearsThem() {
        let model = AppModel.preview()
        show(FlowListView().environment(model))
        XCTAssertEqual(model.visibleFlows.count, 5)
        XCTAssertTrue(elements("Clear Filters").isEmpty, "no summary row while nothing is filtered")

        FilterToken.apply([.status(4)], to: &model.query)
        settle()
        XCTAssertEqual(model.visibleFlows.map(\.response?.status), [401, 403])
        XCTAssertFalse(elements("2 of 5 requests").isEmpty, "the summary says how many are left")

        press("Clear Filters")
        XCTAssertFalse(model.query.isActive)
        XCTAssertEqual(model.visibleFlows.count, 5)
    }

    func testNoMatchesOffersClearFilters() {
        let model = AppModel.preview()
        model.query.text = "no-such-request"
        show(FlowListView().environment(model))
        XCTAssertTrue(model.visibleFlows.isEmpty)
        press("Clear Filters")
        XCTAssertEqual(model.query.text, "")
        XCTAssertEqual(model.visibleFlows.count, 5)
    }

    // MARK: Inspector

    func testInspectorHeaderActions() {
        let model = AppModel.preview()
        model.observeEngine()
        let selected = model.flows[0]
        show(FlowDetailView().environment(model), width: 900)

        press("Star")
        settle(0.3) // the star goes through the store and comes back as an event batch
        XCTAssertTrue(model.flows[0].isStarred)
        XCTAssertFalse(elements("Remove Star").isEmpty, "the button now offers to undo")

        press("Copy as cURL")
        XCTAssertEqual(model.notice?.message, "cURL copied")
        XCTAssertEqual(model.pasteboard.string(forType: .string), model.code(for: selected.request, as: .curl))
        XCTAssertNotEqual(model.pasteboard, NSPasteboard.general, "tests must never write to the real clipboard")

        press("Edit & Repeat")
        XCTAssertEqual(model.sheet, .compose)
        XCTAssertEqual(model.composeDraft?.url, selected.request.url)
    }

    func testNarrowInspectorSwitchesBetweenRequestAndResponse() {
        let model = AppModel.preview()
        model.exchangeSide = .response
        show(FlowDetailView().environment(model), width: 420)
        press("Request")
        XCTAssertEqual(model.exchangeSide, .request)
        press("Response")
        XCTAssertEqual(model.exchangeSide, .response)
    }

    // MARK: Breakpoints

    func testBreakpointRulesCanBeDeletedFromTheWindow() {
        let model = AppModel.preview()
        model.settings.breakpoints = RuleSet(isEnabled: true, rules: [
            BreakpointRule(name: "Login", matching: MatchingRule(pattern: "api.example.com/v1/login")),
            BreakpointRule(name: "Users", matching: MatchingRule(pattern: "*/v1/users*")),
        ])
        show(BreakpointsView().environment(model), width: 900, height: 560)
        XCTAssertEqual(elements("Delete Breakpoint").count, 2)

        press("Delete Breakpoint")
        XCTAssertEqual(model.settings.breakpoints.rules.map(\.name), ["Users"])
        XCTAssertEqual(model.notice?.message, "Breakpoint “Login” removed")
        settle()
        XCTAssertEqual(elements("Delete Breakpoint").count, 1, "the list redraws without the deleted rule")
    }

    func testPausedRequestCanBeContinuedAndItsBreakpointRemoved() {
        let model = AppModel.preview()
        let request = RequestRecord(method: "POST", scheme: "https", host: "api.example.com", port: 443, path: "/v1/login")
        model.settings.breakpoints = RuleSet(isEnabled: true, rules: [BreakpointRule(name: "Login", matching: MatchingRule(pattern: "api.example.com/v1/login"))])
        model.hits = [.init(phase: .request, request: request)]
        show(BreakpointsView().environment(model), width: 900, height: 600)

        press("Remove Breakpoint")
        XCTAssertTrue(model.settings.breakpoints.rules.isEmpty, "the rule that kept pausing is gone")
        XCTAssertNil(model.sheet, "nothing else was opened")
    }

    // MARK: Tools and Settings

    func testToolsAddsARuleAndSwitchesTheToolOn() {
        let model = AppModel(listening: false)
        model.toolsSelection = .block
        show(ToolsView().environment(model), width: 920, height: 620)
        XCTAssertTrue(model.settings.blockList.rules.isEmpty)
        press("Add Rule")
        XCTAssertEqual(model.settings.blockList.rules.count, 1)
        XCTAssertTrue(model.settings.blockList.isEnabled, "a new rule works without a second switch")

        model.settings.blockList.isEnabled = false
        settle()
        press("Turn On")
        XCTAssertTrue(model.settings.blockList.isEnabled)

        press("Remove Rule")
        XCTAssertTrue(model.settings.blockList.rules.isEmpty)
    }

    func testSettingsShowsAndControlsTheProxy() {
        let model = AppModel(listening: false)
        model.settings.port = 70000
        show(SettingsView().environment(model), width: 560, height: 520)
        XCTAssertFalse(elements("Stopped").isEmpty)
        press("Start")
        XCTAssertFalse(model.isRunning, "an invalid port is refused")
        XCTAssertTrue(model.proxyError?.contains("not valid") == true)
        settle()
        XCTAssertFalse(elements("Failed to start").isEmpty, "the status row says it failed")
    }

    // MARK: Welcome

    /// First run: skipping closes the sheet without capturing; Start Capturing remembers the choice and starts the proxy.
    /// (UserDefaults here are xctest's own domain, not Watcher's.)
    func testWelcomeSkipAndStart() {
        let skipping = AppModel(listening: false)
        skipping.onboardingDone = false
        skipping.sheet = .welcome
        show(WelcomeView().environment(skipping), width: 560, height: 460)
        press("Skip for Now")
        XCTAssertTrue(skipping.onboardingDone)
        XCTAssertNil(skipping.sheet)
        XCTAssertFalse(skipping.isRunning, "skipping does not start capturing")
        window?.close()

        let starting = AppModel(listening: false)
        starting.settings.port = PortFinder.firstAvailable(from: 21000) ?? 29998
        try? starting.engine.settings.replace(with: starting.settings)
        starting.onboardingDone = false
        starting.sheet = .welcome
        show(WelcomeView().environment(starting), width: 560, height: 460)
        press("Start Capturing")
        let started = Date()
        while !starting.isRunning, Date().timeIntervalSince(started) < 5 {
            settle(0.1)
        }
        XCTAssertTrue(starting.onboardingDone)
        XCTAssertNil(starting.sheet)
        XCTAssertTrue(starting.isRunning)
        starting.toggleRunning()
        let stopped = Date()
        while starting.isRunning, Date().timeIntervalSince(stopped) < 5 {
            settle(0.1)
        }
    }

    // MARK: About, Devices, Converter, Help, Compare

    /// Types into the first editable text element whose current value starts with `prefix` (empty matches an empty field).
    private func type(_ text: String, intoFieldWithValue prefix: String = "", role: String) -> Bool {
        let app = AXUIElementCreateApplication(getpid())
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        var queue = windows as? [AXUIElement] ?? [], visited = 0
        while !queue.isEmpty, visited < 5000 {
            let element = queue.removeFirst(); visited += 1
            var r: CFTypeRef?; AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &r)
            if r as? String == role {
                var v: CFTypeRef?; AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &v)
                if ((v as? String) ?? "").hasPrefix(prefix) {
                    let ok = AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
                    settle()
                    return ok
                }
            }
            var k: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &k) == .success {
                queue += k as? [AXUIElement] ?? []
            }
        }
        return false
    }

    func testAboutCopiesVersionInfo() {
        let model = AppModel(listening: false)
        show(AboutView().environment(model), width: 480, height: 640)
        XCTAssertFalse(elements("Development build").isEmpty, "an unbundled run says so instead of borrowing another version")
        press("Copy Version Info")
        XCTAssertEqual(model.notice?.message, "Version info copied")
        XCTAssertTrue(model.pasteboard.string(forType: .string)?.hasPrefix("Watcher Development build · macOS") == true)
    }

    func testDevicesOffersToTrustWhenNotTrusted() {
        let model = AppModel(listening: false) // the test probe reports "not trusted" and no devices
        show(DeviceSetupView().environment(model), width: 760, height: 560)
        XCTAssertFalse(elements("Not trusted yet").isEmpty)
        XCTAssertFalse(elements("Install & Trust…").isEmpty, "the action that fixes it is right there")
        XCTAssertTrue(elements("Remove").isEmpty, "nothing to remove while not trusted")
    }

    func testConverterDecodesWhatIsTyped() {
        let model = AppModel(listening: false)
        show(ConverterView().environment(model), width: 640, height: 500)
        XCTAssertTrue(type("aGVsbG8gd2F0Y2hlcg==", role: "AXTextArea"), "the input field accepts text")
        XCTAssertFalse(elements("Converted").isEmpty, "a successful conversion says so")
        XCTAssertTrue(type("%%% not base64", intoFieldWithValue: "aGVs", role: "AXTextArea"))
        XCTAssertFalse(elements("This is not valid Base64.").isEmpty, "bad input is explained, not ignored")
    }

    func testHelpSearchNarrowsTheShortcuts() {
        show(HelpView(), width: 640, height: 560)
        // Each row is read as "title: spoken shortcut", e.g. "Repeat: Command R".
        let repeatRow = "Repeat: \(Shortcut.spoken("⌘R"))"
        let proxyRow = "Record or pause (starts and stops the proxy): \(Shortcut.spoken("⌘E"))"
        XCTAssertFalse(elements(repeatRow).isEmpty)
        XCTAssertTrue(type("proxy", role: "AXTextField"), "the search field accepts text")
        XCTAssertFalse(elements(proxyRow).isEmpty)
        XCTAssertTrue(elements(repeatRow).isEmpty, "unrelated shortcuts are hidden")
    }

    func testCompareSwitchesWhatItCompares() {
        let model = AppModel.preview()
        var other = Flow(sequence: 9, request: model.flows[0].request)
        other.request.headers.append(Header("X-Debug", "1"))
        other.response = model.flows[0].response; other.state = .completed
        model.engine.store.load(model.flows + [other]); model.syncFromStore()
        model.diffBase = model.flows[0]
        model.selection = model.flows.last?.id
        show(CompareWindow().environment(model), width: 900, height: 600)
        settle(1)
        XCTAssertFalse(elements("No Differences").isEmpty, "the response bodies are the same")
        press("Headers")
        settle(1)
        XCTAssertTrue(elements("No Differences").isEmpty, "the added request header shows up as a difference")
        XCTAssertFalse(elements("+1").isEmpty)
    }

    // MARK: Compose

    func testComposeExplainsWhyItCannotSendYet() {
        let model = AppModel(listening: false)
        show(ComposeView().environment(model), width: 900, height: 640)
        XCTAssertFalse(elements("Start Proxy").isEmpty, "the empty response pane offers to start the proxy")
        press("Send")
        settle(0.3)
        XCTAssertFalse(elements("Not Sent").isEmpty, "a send with the proxy stopped shows why")
    }
}

/// The system accessibility API, pointed at this process: what UI automation and VoiceOver use. Inside one process the
/// requests are answered directly on the calling thread, so they run on the main thread like the UI they inspect.
enum AX {
    @MainActor static func find(_ label: String, inWindow _: Int) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 5)
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &windows)
        // Each test shows one window and closes it in tearDown, so every window of the process is that test's.
        let roots = windows as? [AXUIElement] ?? []
        var found: [AXUIElement] = [], queue = roots, visited = 0
        while !queue.isEmpty, visited < 5000 {
            let element = queue.removeFirst(); visited += 1
            for attribute in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
                var value: CFTypeRef?
                if AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, (value as? String) == label {
                    found.append(element); break
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
                queue += children as? [AXUIElement] ?? []
            }
        }
        return found
    }
}
