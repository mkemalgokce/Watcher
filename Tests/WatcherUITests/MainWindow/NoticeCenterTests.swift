import Testing
import WatcherTestSupport
@testable import WatcherUI

/// Short feedback over the window: what is shown, read out, and when it goes away.
@MainActor
@Suite(.tags(.unit))
struct NoticeCenterTests {
    private let gate = SleepGate()
    private let announcer = AnnouncerSpy()

    private func center() -> NoticeCenter {
        NoticeCenter(sleep: gate.sleep, announce: announcer.announce)
    }

    @Test
    func aNoticeIsShownAndReadOut() {
        let center = center()
        center.notify("Saved", .success)
        #expect(center.notice?.message == "Saved")
        #expect(center.notice?.kind == .success)
        #expect(announcer.messages == ["Saved"])
    }

    @Test
    func theKindDefaultsToInfo() {
        let center = center()
        center.notify("Hello")
        #expect(center.notice?.kind == .info)
    }

    @Test(arguments: [
        (Notice.Kind.info, false, Duration.seconds(3)),
        (.success, false, .seconds(3)),
        (.info, true, .seconds(8)),
        (.error, false, .seconds(9)),
        (.error, true, .seconds(9)),
    ])
    func aNoticeGoesAwayAfterItsTime(kind: Notice.Kind, withAction: Bool, after: Duration) async {
        let center = center()
        center.notify("x", kind, action: withAction ? NoticeAction(title: "Undo") {} : nil)
        #expect(await eventually { gate.waitingCount == 1 })
        #expect(gate.durations == [after])
        #expect(center.notice != nil, "still shown while the time runs")
        gate.releaseAll()
        #expect(await eventually { center.notice == nil })
    }

    @Test
    func aNewerNoticeOutlivesTheTimerOfAnOlderOne() async {
        let center = center()
        center.notify("first")
        #expect(await eventually { gate.waitingCount == 1 })
        center.notify("second")
        #expect(await eventually { gate.waitingCount == 2 })
        gate.releaseOldest()
        #expect(await eventually { gate.returnedCount == 1 })
        await Task.yield() // the older timer's check runs on the main actor right after its wait returns
        #expect(center.notice?.message == "second")
        gate.releaseAll()
        #expect(await eventually { center.notice == nil })
    }

    @Test
    func dismissingHidesTheNoticeAtOnce() {
        let center = center()
        center.notify("x", .error)
        center.dismiss()
        #expect(center.notice == nil)
        gate.releaseAll()
    }

    @Test
    func noticesAreDistinctEvenWithTheSameText() {
        let center = center()
        center.notify("same")
        let first = center.notice
        center.notify("same")
        #expect(center.notice != first)
        gate.releaseAll()
    }
}
