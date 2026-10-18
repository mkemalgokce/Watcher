import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension SettingsEditor {
    /// An editor that saves and applies nothing and never debounces, for tests of what reads or edits settings.
    @MainActor
    static func inMemory(
        _ initial: WatcherSettings = WatcherSettings(), notices: NoticeCenter? = nil
    ) -> SettingsEditor {
        SettingsEditor(
            initial: initial, sleep: sleepUntilCancelled, notices: notices ?? .silent(),
            persist: { _ in }, apply: { _ in }
        )
    }
}
