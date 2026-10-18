import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct CharlesConverterTests {
    @Test
    func aMissingCharlesInstallIsReported() async {
        let error = await #expect(throws: CharlesConverter.ConversionError.self) {
            _ = try await CharlesConverter.flows(
                from: URL(fileURLWithPath: "/tmp/x.chls"),
                charles: URL(fileURLWithPath: "/nonexistent/Charles")
            )
        }
        #expect(error.map { "\($0)" }?.contains("not found") == true)
    }
}
