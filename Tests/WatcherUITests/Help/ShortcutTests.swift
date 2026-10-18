import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI

/// The shortcuts Help lists: how VoiceOver reads them, and that they cover every menu shortcut.
@Suite(.tags(.unit))
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
        var missing: [String] = []
        let shortcuts = try MenuShortcut.all(in: source).filter { $0.isCharacter && $0.key.count == 1 }
        #expect(shortcuts.count > 30, "the pattern no longer finds the menu shortcuts")
        for shortcut in shortcuts {
            let key = shortcut.key.uppercased()
            var symbol = ""
            if shortcut.modifiers.contains(".control") {
                symbol += "⌃"
            }
            if shortcut.modifiers.contains(".option") {
                symbol += "⌥"
            }
            if shortcut.modifiers.contains(".shift") {
                symbol += "⇧"
            }
            symbol += "⌘" + key
            // Ranges such as "⌘1 – ⌘4" cover the numbered items.
            let covered = listed.contains(symbol) || listed.contains {
                $0.contains("–") && $0.hasPrefix(String(symbol.dropLast())) && key.allSatisfy(\.isNumber)
            }
            if !covered {
                missing.append(symbol)
            }
        }
        #expect(missing == [], "Add these to Shortcut.groups in Shortcut.swift")
    }
}
