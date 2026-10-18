import WatcherTestSupport
@testable import WatcherUI

extension NoticeCenter {
    /// Notices that are kept until replaced: the timeout never ends and nothing is read out.
    @MainActor
    static func silent() -> NoticeCenter {
        NoticeCenter(sleep: sleepUntilCancelled) { _ in }
    }
}
