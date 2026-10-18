import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RawInflaterTests {
    /// A deflate stream whose first block header is damaged: the decoder reports an error instead of output.
    static let corrupt = Data(hex: "ffc94855282ccd4cce56482aca2fcf5348cbaf50c82acd2d2856c82f4b2d5228014a")

    private func deflated(_ data: Data) throws -> Data {
        try (data as NSData).compressed(using: .zlib) as Data
    }

    @Test
    func rawDeflateIsInflated() throws {
        let text = Data(String(repeating: "hello ", count: 50).utf8)
        #expect(try RawInflater().inflate(deflated(text)) == text)
    }

    @Test
    func emptyInputGivesEmptyOutput() {
        #expect(RawInflater().inflate(Data()) == Data())
    }

    @Test
    func corruptInputIsRefused() {
        #expect(RawInflater().inflate(Self.corrupt) == nil)
    }

    @Test
    func outputBeyondSixteenMegabytesIsRefused() throws {
        let bomb = try deflated(Data(count: 17 * 1024 * 1024))
        #expect(bomb.count < 100_000)
        #expect(RawInflater().inflate(bomb) == nil)
    }
}
