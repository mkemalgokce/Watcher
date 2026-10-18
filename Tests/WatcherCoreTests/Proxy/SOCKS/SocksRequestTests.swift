import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SocksRequestTests {
    private static let longName = [UInt8](repeating: UInt8(ascii: "a"), count: 255)
    private static let documentationAddress: [UInt8] =
        [0x20, 0x01, 0x0D, 0xB8] + [UInt8](repeating: 0, count: 10) + [0xAB, 0xCD]

    private static func request(
        command: UInt8 = 1,
        type: UInt8,
        address: [UInt8],
        port: [UInt8] = [0x1F, 0x90]
    ) -> [UInt8] {
        [5, command, 0, type] + address + port
    }

    @Test(arguments: [
        (request(type: 1, address: [127, 0, 0, 1]), "127.0.0.1", 8080),
        (request(type: 1, address: [10, 20, 30, 40], port: [0x01, 0xBB]), "10.20.30.40", 443),
        (request(type: 1, address: [1, 2, 3, 4], port: [0xFF, 0xFF]), "1.2.3.4", 65535),
        (request(type: 3, address: [5] + Array("a.com".utf8)), "a.com", 8080),
        (request(type: 3, address: [255] + longName), String(repeating: "a", count: 255), 8080),
        (request(type: 4, address: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]), "0:0:0:0:0:0:0:1", 8080),
        (request(type: 4, address: documentationAddress), "2001:db8:0:0:0:0:0:abcd", 8080),
    ] as [([UInt8], String, Int)])
    func anAddressIsReadWithItsPort(bytes: [UInt8], host: String, port: Int) {
        #expect(SocksRequest.parse(bytes) == .connect(host: host, port: port, consumed: bytes.count))
    }

    @Test
    func bytesAfterTheRequestAreLeftUnconsumed() {
        let bytes = Self.request(type: 1, address: [1, 2, 3, 4]) + Array("GET".utf8)
        #expect(SocksRequest.parse(bytes) == .connect(host: "1.2.3.4", port: 8080, consumed: 10))
    }

    @Test(arguments: [2, 3, 0, 255] as [UInt8])
    func aCommandOtherThanConnectIsRefusedWithCode7(command: UInt8) {
        let bytes = Self.request(command: command, type: 1, address: [1, 2, 3, 4])
        #expect(SocksRequest.parse(bytes) == .unsupported(code: 7))
    }

    @Test(arguments: [0, 2, 5, 255] as [UInt8])
    func anUnknownAddressTypeIsRefusedWithCode8(type: UInt8) {
        #expect(SocksRequest.parse(Self.request(type: type, address: [1, 2, 3, 4])) == .unsupported(code: 8))
    }

    @Test(arguments: [[0], [2, 0xFF, 0xFE]] as [[UInt8]])
    func aDomainThatIsEmptyOrNotUTF8IsRefusedAsUnreachable(address: [UInt8]) {
        #expect(SocksRequest.parse(Self.request(type: 3, address: address)) == .unsupported(code: 4))
    }

    @Test
    func aWrongVersionIsRefused() {
        #expect(SocksRequest.parse([4, 1, 0, 1, 1, 2, 3, 4, 0, 80]) == .unsupported(code: 7))
    }

    @Test(arguments: [
        [], [5], [5, 1, 0], [5, 1, 0, 1, 1, 2, 3, 4, 0], [5, 1, 0, 3], [5, 1, 0, 3, 5, 97, 46, 99, 111, 109, 0],
        [5, 1, 0, 4] + Array(repeating: 0, count: 17),
    ] as [[UInt8]])
    func aTruncatedRequestWaitsForMoreBytes(bytes: [UInt8]) {
        #expect(SocksRequest.parse(bytes) == .needMoreBytes)
    }
}
