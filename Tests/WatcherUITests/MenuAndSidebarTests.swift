import AppKit
import SwiftUI
@testable import WatcherCore
@testable import WatcherUI
import XCTest

/// The menus and the sidebar: shortcuts that are unique and listed in Help, a menu bar item that cannot loop at launch,
/// and a sidebar selection that survives arriving traffic.
@MainActor
final class MenuAndSidebarTests: XCTestCase {
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
                .appendingPathComponent("../../Sources/WatcherUI/App/WatcherCommands.swift").standardized,
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
                .appendingPathComponent("../../Sources/WatcherUI/App/WatcherCommands.swift").standardized,
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
