import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension SettingsEditorTests {
    /// Fields read and written straight on the editor go through its value.
    @MainActor
    struct Fields {
        private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }

        @Test
        func aFieldWrittenOnTheEditorChangesTheValue() {
            let editor = SettingsEditor(
                initial: WatcherSettings(),
                sleep: SleepSpy().sleep,
                notices: notices,
                persist: { _ in },
                apply: { _ in }
            )
            editor.port = 4321
            #expect(editor.value.port == 4321)
            #expect(editor.port == 4321)
        }

        @Test
        func theEngineEditorSavesToTheEngine() async throws {
            let engine = try WatcherEngine.inMemory()
            let editor = SettingsEditor(engine: engine, sleep: SleepSpy().sleep, notices: notices)
            #expect(editor.value == engine.settings.value)
            editor.maxFlows = 1234
            #expect(await eventually { engine.settings.value.maxFlows == 1234 })
        }
    }
}
