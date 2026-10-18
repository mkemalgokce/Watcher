import Foundation
import Testing
import WatcherTestSupport

/// The menu commands, read from their source.
@Suite(.tags(.unit))
struct WatcherCommandsTests {
    /// Two menu items on one key combination means one of them silently never fires.
    @Test
    func menuShortcutsAreUnique() throws {
        let source = try SourceTree.text("Sources/WatcherUI/App/WatcherCommands.swift")
        var seen: [String: Int] = [:]
        for shortcut in try MenuShortcut.all(in: source) {
            seen["\(shortcut.modifiers.joined(separator: ","))+\(shortcut.key.lowercased())", default: 0] += 1
        }
        #expect(seen.count > 30)
        #expect(seen.filter { $0.value > 1 }.keys.sorted() == [], "these key combinations are used twice")
    }
}
