import Foundation
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension ShortcutTests {
    /// A shortcut named in the interface must be one a menu or view really binds, and Help must not list a dead one.
    @Suite(.tags(.unit))
    struct Usage {
        /// Bound by something other than a `.keyboardShortcut("x")` call: the standard Settings item and Escape.
        private static let systemShortcuts: Set<String> = ["⌘,", "⎋"]
        private static let namedKeys = [".delete": "⌫", ".return": "↩", ".escape": "⎋", ".defaultAction": "↩"]

        private static func symbol(for shortcut: MenuShortcut) -> String {
            let key = shortcut.isCharacter ? shortcut.key.uppercased() : namedKeys[shortcut.key, default: shortcut.key]
            let order = [(".control", "⌃"), (".option", "⌥"), (".shift", "⇧"), (".command", "⌘")]
            return order.filter { shortcut.modifiers.contains($0.0) }.map(\.1).joined() + key
        }

        private static func sourceFiles() throws -> [String] {
            let root = SourceTree.url("Sources/WatcherUI")
            let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?.allObjects as? [URL]
            return try (files ?? []).filter { $0.pathExtension == "swift" }
                .map { try String(contentsOf: $0, encoding: .utf8) }
        }

        private static func bound() throws -> Set<String> {
            try Set(sourceFiles().flatMap { try MenuShortcut.all(in: $0) }.map(symbol(for:))).union(systemShortcuts)
        }

        private static func displayed(in source: String) throws -> [String] {
            let patterns = [#"shortcut: "([^"\\]+)""#, #"\(([⌃⌥⇧⌘][⌃⌥⇧⌘]*[^\s)\\]+)\)"#]
            return try patterns.flatMap { pattern -> [String] in
                let expression = try NSRegularExpression(pattern: pattern)
                return expression.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap {
                    Range($0.range(at: 1), in: source).map { String(source[$0]) }
                }
            }
        }

        @Test
        func everyShortcutShownInTheInterfaceIsBound() throws {
            let bound = try Self.bound()
            let shown = try Set(Self.sourceFiles().flatMap(Self.displayed(in:)))
            #expect(shown.count > 15, "the pattern no longer finds the shortcuts shown in the interface")
            #expect(shown.subtracting(bound).sorted() == [])
        }

        @Test
        func everyShortcutHelpListsIsBound() throws {
            let bound = try Self.bound()
            let listed = Shortcut.groups.flatMap(\.items).map(\.keys)
            let unbound = listed.filter { keys in
                let first = keys.components(separatedBy: " – ")[0]
                return !bound.contains(first)
            }
            #expect(unbound == [], "Help lists shortcuts nothing binds: update Shortcut.groups in Shortcut.swift")
        }
    }
}
