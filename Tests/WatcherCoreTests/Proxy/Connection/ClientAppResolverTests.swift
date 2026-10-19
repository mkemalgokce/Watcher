import NIO
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientAppResolverTests {
    private static let curl = ClientIdentity(app: "curl", process: "curl", kind: .tool, bundlePath: nil)
    private let asked = LockedBox<[Int]>([])

    private func resolver(answer: ClientIdentity? = curl, local: Set<String> = ["192.168.1.5"]) -> ClientAppResolver {
        ClientAppResolver(localAddresses: { local }) { [asked] port in
            asked.mutate { $0.append(port) }
            return answer
        }
    }

    private func channel(from address: String, port: Int = 54321) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        channel.remoteAddress = try SocketAddress(ipAddress: address, port: port)
        return channel
    }

    @Test(arguments: ["127.0.0.1", "::1", "192.168.1.5"])
    func aLocalClientIsLookedUpByItsPortOnceAndRemembered(address: String) async throws {
        let channel = try channel(from: address)
        let resolver = resolver()
        #expect(await resolver.identity(for: channel) == Self.curl)
        #expect(await resolver.identity(for: channel) == Self.curl)
        #expect(asked.value == [54321])
    }

    @Test
    func anUnknownLocalProgramIsRememberedToo() async throws {
        let channel = try channel(from: "127.0.0.1")
        let resolver = resolver(answer: nil)
        #expect(await resolver.identity(for: channel) == nil)
        #expect(await resolver.identity(for: channel) == nil)
        #expect(asked.value == [54321])
    }

    @Test
    func aDualStackListenerSeesLocalIPv4ClientsAsMappedAddressesAndStillLooksThemUp() async throws {
        for address in ["::ffff:127.0.0.1", "::ffff:192.168.1.5"] {
            #expect(try await resolver().identity(for: channel(from: address)) == Self.curl)
        }
        #expect(asked.value == [54321, 54321])
    }

    @Test
    func aMappedAddressOfAnotherMachineIsADeviceNamedByItsIPv4Address() async throws {
        let device = ClientIdentity(app: "192.168.1.77", process: "192.168.1.77", kind: .device, bundlePath: nil)
        #expect(try await resolver().identity(for: channel(from: "::ffff:192.168.1.77")) == device)
        #expect(asked.value.isEmpty)
    }

    @Test(arguments: ["192.168.1.77", "2001:db8::1"])
    func aClientOnAnotherMachineIsADeviceNamedByItsAddressAndNeverLookedUp(address: String) async throws {
        let device = ClientIdentity(app: address, process: address, kind: .device, bundlePath: nil)
        #expect(try await resolver().identity(for: channel(from: address)) == device)
        #expect(asked.value.isEmpty)
    }

    @Test
    func aChannelWithoutAPeerHasNoIdentity() async {
        #expect(await resolver().identity(for: EmbeddedChannel()) == nil)
        #expect(asked.value.isEmpty)
    }
}
