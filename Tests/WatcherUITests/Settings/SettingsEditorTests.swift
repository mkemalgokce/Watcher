import Foundation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The window's editable copy of the settings: edits are saved and applied together after a short pause.
@MainActor
@Suite(.tags(.unit))
struct SettingsEditorTests {
    private let gate = SleepGate()
    private let notices = NoticeCenter(sleep: sleepUntilCancelled) { _ in }
    private let saved = LockedBox<[WatcherSettings]>([])
    private let applied = LockedBox<[WatcherSettings]>([])

    private func editor(failingWith error: (any Error)? = nil) -> SettingsEditor {
        let saved = saved, applied = applied
        return SettingsEditor(
            initial: WatcherSettings(),
            sleep: gate.sleep,
            notices: notices,
            persist: { settings in
                if let error {
                    throw error
                }
                saved.mutate { $0.append(settings) }
            },
            apply: { settings in applied.mutate { $0.append(settings) } }
        )
    }

    @Test
    func editsInsideThePauseAreCommittedOnce() async {
        let editor = editor()
        editor.value.port = 1001
        editor.value.port = 1002
        editor.value.port = 1003
        #expect(await eventually { gate.waitingCount == 3 })
        #expect(gate.durations == Array(repeating: .milliseconds(400), count: 3))
        gate.releaseAll()
        #expect(await eventually { applied.value.count == 1 })
        #expect(saved.value.map(\.port) == [1003])
        #expect(applied.value.map(\.port) == [1003])
    }

    @Test
    func nothingIsCommittedBeforeThePauseEnds() async {
        let editor = editor()
        editor.value.port = 1001
        #expect(await eventually { gate.waitingCount == 1 })
        #expect(saved.value.isEmpty)
        gate.releaseAll()
        #expect(await eventually { saved.value.count == 1 })
    }

    @Test
    func aFailedSaveBecomesAnErrorNoticeAndIsNotApplied() async {
        struct DiskFull: Error {}
        let editor = editor(failingWith: DiskFull())
        editor.value.port = 1001
        #expect(await eventually { gate.waitingCount == 1 })
        gate.releaseAll()
        #expect(await eventually { notices.notice?.kind == .error })
        #expect(applied.value.isEmpty)
    }

    @Test
    func changesAreReportedWithTheOldAndNewValue() {
        let editor = editor()
        var seen: [(Bool, Bool)] = []
        editor.onChange = { old, new in seen.append((old.hideAppleTraffic, new.hideAppleTraffic)) }
        let before = editor.value.hideAppleTraffic
        editor.value.hideAppleTraffic.toggle()
        #expect(seen.count == 1)
        #expect(seen.first?.0 == before)
        #expect(seen.first?.1 == !before)
        gate.releaseAll()
    }

    @Test(arguments: [10000, nil] as [Int?])
    func aReverseProxyPortSuggestionComesFromTheEngine(port: Int?) {
        let editor = SettingsEditor(
            initial: WatcherSettings(), sleep: gate.sleep, notices: notices,
            persist: { _ in }, apply: { _ in }, suggestReversePort: { port }
        )
        #expect(editor.suggestReversePort() == port)
    }
}
