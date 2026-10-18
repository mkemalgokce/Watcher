import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct PillTests {
    @Test
    func statusPillLooksTheSame() async {
        let pill = Pill(text: "404", tint: .orange, monospaced: true)
        await ImageSnapshot.verify(pill, size: CGSize(width: 60, height: 24), named: "status")
    }

    @Test
    func tagPillLooksTheSame() async {
        await ImageSnapshot.verify(Pill(text: "Map Local"), size: CGSize(width: 90, height: 24), named: "tag")
    }
}
