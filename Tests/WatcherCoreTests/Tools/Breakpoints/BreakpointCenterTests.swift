import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit), .timeLimit(.minutes(1)))
struct BreakpointCenterTests {
    private static let pausedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private static let ids = (1 ... 9).map { UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)") ?? UUID() }
    private let center: BreakpointCenter = {
        let next = LockedBox(0)
        return BreakpointCenter(now: { pausedAt }, makeID: {
            next.mutate { $0 += 1 }
            return ids[next.value - 1]
        })
    }()

    /// Holds `request` in the background and returns once the center lists it.
    private func held(_ request: RequestRecord = .fixture()) async throws -> Task<BreakpointCenter.Resolution, Never> {
        let count = center.pending.count
        let task = Task { [center] in await center.hold(phase: .request, request: request) }
        try #require(await eventually { center.pending.count == count + 1 })
        return task
    }

    @Test
    func aHeldRequestIsListedWithItsIDAndPauseTime() async throws {
        let task = try await held()
        let hit = try #require(center.pending.first)
        #expect(hit.id == Self.ids[0])
        #expect(hit.pausedAt == Self.pausedAt)
        #expect(hit.phase == .request)
        center.resolve(hit.id, with: .abort)
        _ = await task.value
    }

    @Test
    func resolvingAnswersTheHolderWithTheEditAndUnlistsIt() async throws {
        let task = try await held()
        let edited = RequestRecord.fixture(path: "/edited")
        center.resolve(Self.ids[0], with: .proceed(request: edited, response: nil))
        guard case let .proceed(request, response) = await task.value else {
            Issue.record("expected the edit to proceed"); return
        }
        #expect(request.path == "/edited")
        #expect(response == nil)
        #expect(center.pending.isEmpty)
    }

    @Test
    func resolvingAnUnknownIDChangesNothing() async throws {
        let task = try await held()
        center.resolve(UUID(), with: .abort)
        #expect(center.pending.count == 1)
        center.releaseAll()
        _ = await task.value
    }

    @Test
    func releaseAllLetsEveryHeldMessageThroughUnchanged() async throws {
        let first = try await held(.fixture(path: "/a")), second = try await held(.fixture(path: "/b"))
        center.releaseAll()
        for (task, path) in [(first, "/a"), (second, "/b")] {
            guard case let .proceed(request, _) = await task.value else {
                Issue.record("expected \(path) to proceed"); continue
            }
            #expect(request.path == path)
        }
        #expect(center.pending.isEmpty)
    }

    @Test
    func abortAllAbortsEveryHeldMessage() async throws {
        let first = try await held(), second = try await held()
        center.abortAll()
        for task in [first, second] {
            guard case .abort = await task.value else { Issue.record("expected an abort"); continue }
        }
    }

    @Test
    func observersHearAboutEachHoldAndResolution() async throws {
        var changes = center.changes().makeAsyncIterator()
        let task = try await held()
        #expect(await changes.next() != nil)
        center.resolve(Self.ids[0], with: .abort)
        #expect(await changes.next() != nil)
        _ = await task.value
    }
}
