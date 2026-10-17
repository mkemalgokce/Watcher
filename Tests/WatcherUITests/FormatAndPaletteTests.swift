import SwiftUI
@testable import WatcherUI
import XCTest

final class FormatAndPaletteTests: XCTestCase {
    func testBytesReadExactlyForSmallAndEmptyBodies() {
        XCTAssertEqual(Format.bytes(0), "0 B", "an empty body reads as empty, not \"Zero KB\"")
        XCTAssertEqual(Format.bytes(69), "69 B")
        XCTAssertEqual(Format.bytes(999), "999 B")
        XCTAssertNotEqual(Format.bytes(1000), "1000 B")
    }

    func testDurations() {
        XCTAssertEqual(Format.duration(0.184), "184 ms")
        XCTAssertEqual(Format.duration(0), "0 ms")
        XCTAssertEqual(Format.duration(5), "5.00 s")
    }

    func testStatusColoursFollowTheStatusClass() {
        XCTAssertEqual(Palette.status(204), Palette.success)
        XCTAssertEqual(Palette.status(304), Palette.redirect)
        XCTAssertEqual(Palette.status(404), Palette.clientError)
        XCTAssertEqual(Palette.status(503), Palette.serverError)
        XCTAssertEqual(Palette.status(nil), Palette.pending)
        XCTAssertEqual(Palette.status(200, failed: true), Palette.serverError, "a failed exchange is never shown as a success")
        XCTAssertEqual(Palette.status(99), Palette.pending)
    }

    func testMethodColoursGoFromSafeToDestructive() {
        XCTAssertEqual(Palette.method("get"), Palette.method("HEAD"))
        XCTAssertEqual(Palette.method("DELETE"), .red)
        XCTAssertEqual(Palette.method("PATCH"), Palette.method("PUT"))
        XCTAssertEqual(Palette.method("PROPFIND"), .secondary)
    }

    func testSpokenShortcutsReadTheModifiers() {
        XCTAssertEqual(Shortcut.spoken("⇧⌘P"), "Shift Command P")
        XCTAssertEqual(Shortcut.spoken("⌥⌘1 – ⌥⌘5"), "Option Command 1  to  Option Command 5")
    }
}
