import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRunOnThisOS, "no references for this macOS and recording is off")
)
struct PillTests {
    @Test
    func statusPillLooksTheSame() {
        let pill = Pill(text: "404", tint: .orange, monospaced: true)
        ImageSnapshot.verify(pill, size: CGSize(width: 60, height: 24), named: "status")
    }

    @Test
    func tagPillLooksTheSame() {
        ImageSnapshot.verify(Pill(text: "Map Local"), size: CGSize(width: 90, height: 24), named: "tag")
    }
}
