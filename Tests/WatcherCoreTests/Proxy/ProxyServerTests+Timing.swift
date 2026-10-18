import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension ProxyServerTests {
    @Suite(.timeLimit(.minutes(1)))
    struct Timing {
        @Test
        func aFlowAnsweredByAToolLastsAsLongAsTheClockSays() async throws {
            let ticks = LockedBox(0.0)
            let server = ProxyServer(authority: nil, now: {
                ticks.mutate { $0 += 1.5 }
                return Date(timeIntervalSince1970: ticks.value)
            })
            server.tools.set([ToolStub(decision: .respond(ResponseRecord(status: 200, headers: [], body: Data())))])
            _ = await server.process(.fixture())
            #expect(server.store.all.first?.duration == 1.5)
            try await server.stop()
        }
    }
}
