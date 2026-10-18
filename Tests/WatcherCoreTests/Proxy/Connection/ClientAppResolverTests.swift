import Foundation
import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientAppResolverTests {
    private let asked = LockedBox<[Int]>([])

    private func resolver(answer: String? = "curl") -> ClientAppResolver {
        ClientAppResolver { [asked] port in
            asked.mutate { $0.append(port) }
            return answer
        }
    }

    @Test
    func theProgramIsLookedUpByThePeerPortOnceAndRemembered() async throws {
        let channel = EmbeddedChannel()
        channel.remoteAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 54321)
        let resolver = resolver()
        #expect(await resolver.app(for: channel) == "curl")
        #expect(await resolver.app(for: channel) == "curl")
        #expect(asked.value == [54321])
    }

    @Test
    func anUnknownProgramIsRememberedToo() async throws {
        let channel = EmbeddedChannel()
        channel.remoteAddress = try SocketAddress(ipAddress: "127.0.0.1", port: 54321)
        let resolver = resolver(answer: nil)
        #expect(await resolver.app(for: channel) == nil)
        #expect(await resolver.app(for: channel) == nil)
        #expect(asked.value == [54321])
    }

    @Test
    func aChannelWithoutAPeerNamesNoProgram() async {
        #expect(await resolver().app(for: EmbeddedChannel()) == nil)
        #expect(asked.value.isEmpty)
    }
}
