import SwiftUI
import Testing
@testable import WatcherUI

/// The colours that tell a status or a method apart at a glance.
struct PaletteTests {
    @Test
    func statusColoursFollowTheStatusClass() {
        #expect(Palette.status(204) == Palette.success)
        #expect(Palette.status(304) == Palette.redirect)
        #expect(Palette.status(404) == Palette.clientError)
        #expect(Palette.status(503) == Palette.serverError)
        #expect(Palette.status(nil) == Palette.pending)
        #expect(
            Palette.status(200, failed: true) == Palette.serverError,
            "a failed exchange is never shown as a success"
        )
        #expect(Palette.status(99) == Palette.pending)
    }

    @Test
    func methodColoursGoFromSafeToDestructive() {
        #expect(Palette.method("get") == Palette.method("HEAD"))
        #expect(Palette.method("DELETE") == .red)
        #expect(Palette.method("PATCH") == Palette.method("PUT"))
        #expect(Palette.method("PROPFIND") == .secondary)
    }
}
