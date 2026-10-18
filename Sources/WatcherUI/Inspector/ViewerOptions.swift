import Observation

/// How bodies and message panels are shown, kept between launches in the injected preferences. The viewer,
/// Settings ▸ Viewer and the View menu share one instance, so a change in one shows in the others at once.
@MainActor @Observable
final class ViewerOptions {
    typealias Section = MessagePanel.Section

    var mode: BodyMode {
        didSet { preferences.set(mode.rawValue, forKey: "body.mode") }
    }

    var wrapsLines: Bool {
        didSet { preferences.set(wrapsLines, forKey: "body.wrap") }
    }

    var sortsKeys: Bool {
        didSet { preferences.set(sortsKeys, forKey: "body.sortKeys") }
    }

    var fontSize: Double {
        didSet { preferences.set(fontSize, forKey: "body.fontSize") }
    }

    /// The JSON path / jq field stays hidden until asked for (⇧⌘J), keeping one control row less above every body.
    var showsJSONFilter: Bool {
        didSet { preferences.set(showsJSONFilter, forKey: "body.jsonFilter") }
    }

    private var sections: [MessageSide: Section]
    @ObservationIgnored private let preferences: any Preferences

    init(preferences: any Preferences) {
        self.preferences = preferences
        mode = (preferences.object(forKey: "body.mode") as? String).flatMap(BodyMode.init) ?? .preview
        wrapsLines = preferences.object(forKey: "body.wrap") as? Bool ?? true
        sortsKeys = preferences.object(forKey: "body.sortKeys") as? Bool ?? false
        fontSize = preferences.object(forKey: "body.fontSize") as? Double ?? 12
        showsJSONFilter = preferences.object(forKey: "body.jsonFilter") as? Bool ?? false
        sections = Dictionary(uniqueKeysWithValues: MessageSide.allCases.map { side in
            (side, (preferences.object(forKey: Self.sectionKey(side)) as? String).flatMap(Section.init) ?? .body)
        })
    }

    /// The section last chosen on this side; the panel still falls back when the exchange lacks it.
    func section(for side: MessageSide) -> Section {
        sections[side] ?? .body
    }

    func choose(_ section: Section, for side: MessageSide) {
        sections[side] = section
        preferences.set(section.rawValue, forKey: Self.sectionKey(side))
    }

    func toggleJSONFilter() {
        showsJSONFilter.toggle()
    }

    func toggleLineWrapping() {
        wrapsLines.toggle()
    }

    private static func sectionKey(_ side: MessageSide) -> String {
        "panel.\(side.rawValue).section"
    }
}
