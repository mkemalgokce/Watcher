import Testing
@testable import WatcherUI

struct ResizableSplitTests {
    private func clamp(_ size: Double, total: Double = 1000) -> Double {
        ResizableSplit<Never, Never>.clamped(size, total: total, minFirst: 300, minSecond: 200)
    }

    @Test func keepsASizeThatFits() {
        #expect(clamp(400) == 400)
    }

    @Test func raisesASizeBelowTheSecondMinimum() {
        #expect(clamp(50) == 200)
    }

    @Test func leavesTheFirstPaneItsMinimum() {
        #expect(clamp(900) == 699)
    }

    @Test func inATinyWindowTheFirstPaneWins() {
        #expect(clamp(400, total: 400) == 99)
    }

    @Test func neverGoesNegative() {
        #expect(clamp(400, total: 100) == 0)
    }
}
