import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// The shortcuts Help lists: how VoiceOver reads them, and that they cover every menu shortcut.
struct ShortcutTests {
    @Test
    func spokenShortcutsReadTheModifiers() {
        #expect(Shortcut.spoken("⇧⌘P") == "Shift Command P")
        #expect(Shortcut.spoken("⌥⌘1 – ⌥⌘5") == "Option Command 1  to  Option Command 5")
    }

    /// The Help page lists every menu shortcut, so the list cannot silently fall behind the menus.
    @Test
    func helpListsEveryMenuShortcut() throws {
        let source = try SourceTree.text("Sources/WatcherUI/App/WatcherCommands.swift")
        let listed = Set(Shortcut.groups.flatMap(\.items).map(\.keys))
        let pattern = try NSRegularExpression(pattern: #"\.keyboardShortcut\("(.)"(?:, modifiers: \[?([^)\]]*)\]?)?\)"#)
        var missing: [String] = []
        let matches = pattern.matches(in: source, range: NSRange(source.startIndex..., in: source))
        #expect(matches.count > 30, "the pattern no longer finds the menu shortcuts")
        for match in matches {
            let key = try String(source[#require(Range(match.range(at: 1), in: source))]).uppercased()
            let modifiers = try match.range(at: 2).location == NSNotFound ? ".command"
                : String(source[#require(Range(match.range(at: 2), in: source))])
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
            let covered = listed.contains(symbol) || listed.contains {
                $0.contains("–") && $0.hasPrefix(String(symbol.dropLast())) && key.allSatisfy(\.isNumber)
            }
            if !covered {
                missing.append(symbol)
            }
        }
        #expect(missing == [], "Add these to Shortcut.groups in HelpView.swift")
    }
}
