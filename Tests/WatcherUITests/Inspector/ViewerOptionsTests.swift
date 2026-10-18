import Testing
import WatcherTestSupport
@testable import WatcherUI

/// How bodies are shown: read from the injected preferences, written back on every change, and shared by the viewer,
/// Settings ▸ Viewer and the View menu.
@MainActor
@Suite(.tags(.unit))
struct ViewerOptionsTests {
    @Test
    func defaultsBeforeAnythingIsStored() {
        let options = ViewerOptions(preferences: PreferencesFake())
        #expect(options.mode == .preview)
        #expect(options.wrapsLines)
        #expect(!options.sortsKeys)
        #expect(options.fontSize == 12)
        #expect(!options.showsJSONFilter)
        #expect(options.section(for: .request) == .body)
        #expect(options.section(for: .response) == .body)
    }

    @Test
    func storedChoicesAreReadBack() {
        let preferences = PreferencesFake([
            "body.mode": "Hex", "body.wrap": false, "body.sortKeys": true, "body.fontSize": 15.0,
            "body.jsonFilter": true, "panel.request.section": "Headers", "panel.response.section": "Raw",
        ])
        let options = ViewerOptions(preferences: preferences)
        #expect(options.mode == .hex)
        #expect(!options.wrapsLines)
        #expect(options.sortsKeys)
        #expect(options.fontSize == 15)
        #expect(options.showsJSONFilter)
        #expect(options.section(for: .request) == .headers)
        #expect(options.section(for: .response) == .raw)
    }

    @Test(arguments: [
        ["body.mode": "Sideways"],
        ["body.mode": 3, "body.wrap": "yes", "body.fontSize": "big", "panel.request.section": "Nowhere"],
    ] as [[String: Any]])
    func unreadableValuesFallBackToTheDefaults(stored: [String: Any]) {
        let options = ViewerOptions(preferences: PreferencesFake(stored))
        #expect(options.mode == .preview)
        #expect(options.wrapsLines)
        #expect(options.fontSize == 12)
        #expect(options.section(for: .request) == .body)
    }

    @Test(arguments: BodyMode.allCases)
    func choosingAModeStoresItsName(mode: BodyMode) {
        let preferences = PreferencesFake()
        ViewerOptions(preferences: preferences).mode = mode
        #expect(preferences.values["body.mode"] as? String == mode.rawValue)
    }

    @Test
    func everyChangeIsWrittenBack() {
        let preferences = PreferencesFake()
        let options = ViewerOptions(preferences: preferences)
        options.sortsKeys = true
        options.fontSize = 18
        options.choose(.cookies, for: .request)
        options.choose(.messages, for: .response)
        #expect(preferences.values["body.sortKeys"] as? Bool == true)
        #expect(preferences.values["body.fontSize"] as? Double == 18)
        #expect(preferences.values["panel.request.section"] as? String == "Cookies")
        #expect(preferences.values["panel.response.section"] as? String == "Messages")
        #expect(options.section(for: .request) == .cookies)
    }

    @Test
    func theJSONFilterStartsOffAndToggles() {
        let preferences = PreferencesFake()
        let options = ViewerOptions(preferences: preferences)
        options.toggleJSONFilter()
        #expect(preferences.values["body.jsonFilter"] as? Bool == true)
        options.toggleJSONFilter()
        #expect(preferences.values["body.jsonFilter"] as? Bool == false)
    }

    @Test
    func lineWrappingStartsOnAndToggles() {
        let preferences = PreferencesFake()
        let options = ViewerOptions(preferences: preferences)
        options.toggleLineWrapping()
        #expect(preferences.values["body.wrap"] as? Bool == false)
        options.toggleLineWrapping()
        #expect(preferences.values["body.wrap"] as? Bool == true)
    }
}
