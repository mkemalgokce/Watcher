import Foundation
import SnapshotTesting
import Testing
import WatcherCore
import WatcherTestSupport

@Suite(.tags(.snapshot))
struct CodeGeneratorTests {
    private static let request = RequestRecord.fixture(
        method: "POST",
        url: "https://api.example.com/v1/users?page=2&sort=name",
        headers: [Header("Content-Type", "application/json"), Header("Authorization", "Bearer it's-a-token")],
        body: Data(#"{"name":"O'Brien","tags":["a","b"]}"#.utf8)
    )

    @Test(arguments: CodeGenerator.Language.allCases)
    func generatedCodeForAFixedRequestStaysTheSame(in language: CodeGenerator.Language) {
        assertSnapshot(of: CodeGenerator.generate(Self.request, as: language), as: .lines, named: "\(language)")
    }
}
