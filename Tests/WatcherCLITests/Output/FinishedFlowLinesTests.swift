import Foundation
import Testing
@testable import watcher_cli
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FinishedFlowLinesTests {
    @Test(arguments: [
        (0.0, [String](), "7  200  GET  https://api.example.com/7  0ms"),
        (0.0425, [], "7  200  GET  https://api.example.com/7  42ms"),
        (1.5, ["Map Local"], "7  200  GET  https://api.example.com/7  1500ms  [Map Local]"),
        (0.01, ["Breakpoint", "Rewrite"], "7  200  GET  https://api.example.com/7  10ms  [Breakpoint, Rewrite]"),
    ])
    func aFinishedFlowIsSequenceStatusMethodURLTimeAndTools(duration: Double, tools: [String], line: String) {
        var flow = Flow.fixture(sequence: 7, status: 200)
        flow.duration = duration
        flow.appliedTools = tools
        var lines = FinishedFlowLines()
        #expect(lines.line(for: .updated(flow)) == line)
    }

    @Test
    func aFlowWithoutADurationTakesZeroMilliseconds() {
        var lines = FinishedFlowLines()
        let line = lines.line(for: .updated(.fixture(sequence: 1, status: 404)))
        #expect(line == "1  404  GET  https://api.example.com/1  0ms")
    }

    @Test
    func aFlowIsPrintedOnceThoughItUpdatesAgain() {
        let flow = Flow.fixture(sequence: 1, status: 200)
        var lines = FinishedFlowLines()
        #expect(lines.line(for: .updated(flow)) != nil)
        #expect(lines.line(for: .updated(flow)) == nil)
        #expect(lines.line(for: .updated(.fixture(sequence: 2, status: 200))) != nil)
    }

    @Test
    func aPendingFlowWaitsUntilItFinishes() {
        var flow = Flow.fixture(sequence: 1, status: 200)
        flow.state = .pending
        var lines = FinishedFlowLines()
        #expect(lines.line(for: .updated(flow)) == nil)
        flow.state = .completed
        #expect(lines.line(for: .updated(flow)) != nil)
    }

    @Test
    func aFlowThatGotNoResponseIsNotPrinted() {
        var lines = FinishedFlowLines()
        #expect(lines.line(for: .updated(.fixture(sequence: 1, status: nil))) == nil)
    }

    @Test
    func addedRemovedAndClearedEventsPrintNothing() {
        let flow = Flow.fixture(sequence: 1, status: 200)
        var lines = FinishedFlowLines()
        #expect(lines.line(for: .added(flow)) == nil)
        #expect(lines.line(for: .removed(flow.id)) == nil)
        #expect(lines.line(for: .cleared) == nil)
        #expect(lines.line(for: .updated(flow)) != nil, "an added flow is still printed once it finishes")
    }
}
