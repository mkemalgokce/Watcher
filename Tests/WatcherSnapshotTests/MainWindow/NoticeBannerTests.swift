import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The notice banner for each kind of notice.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct NoticeBannerTests {
    @Test(arguments: [Notice.Kind.success, .info, .error])
    func noticeBannerForEachKind(kind: Notice.Kind) throws {
        let model = try AppModel.test()
        model.notices.notify("Saved 12 requests to session.watcher", kind)
        ImageSnapshot.verify(
            NoticeBanner().environment(model).padding(8),
            size: CGSize(width: 460, height: 64),
            named: "\(kind)"
        )
    }
}
