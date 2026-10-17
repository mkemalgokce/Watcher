import Foundation
import Testing
import WatcherTestSupport

/// The menu commands, read from their source.
struct WatcherCommandsTests {
    /// Two menu items on one key combination means one of them silently never fires.
    @Test
    func menuShortcutsAreUnique() throws {
        let source = try SourceTree.text("Sources/WatcherUI/App/WatcherCommands.swift")
        let pattern = try NSRegularExpression(
            pattern: #"\.keyboardShortcut\(("[^"]*"|\.\w+)(?:, modifiers: \[?([^)\]]*)\]?)?\)"#
        )
        var seen: [String: Int] = [:]
        for match in pattern.matches(in: source, range: NSRange(source.startIndex..., in: source)) {
            let key = try String(source[#require(Range(match.range(at: 1), in: source))]).lowercased()
            let modifiers = try match.range(at: 2).location == NSNotFound ? ".command"
                : String(source[#require(Range(match.range(at: 2), in: source))])
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .sorted()
                .joined(separator: ",")
            seen["\(modifiers)+\(key)", default: 0] += 1
        }
        #expect(seen.count > 30)
        #expect(seen.filter { $0.value > 1 }.keys.sorted() == [], "these key combinations are used twice")
    }
}
