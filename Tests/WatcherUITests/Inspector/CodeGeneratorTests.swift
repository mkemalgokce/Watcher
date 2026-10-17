import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

/// The cURL the inspector shows, on one line or split over several.
struct CodeGeneratorTests {
    @Test
    func multilineCurlKeepsOptionsWithTheirValues() {
        let request = RequestRecord.fixture(
            method: "POST",
            path: "/v1",
            headers: [Header("Accept", "*/*"), Header("Accept-Encoding", "gzip")],
            body: Data("x=1".utf8)
        )
        let code = CodeGenerator.generate(request, as: .curl, multiline: true)
        #expect(code == """
        curl 'https://api.example.com/v1' \\
          -H 'Accept: */*' \\
          --compressed \\
          --data-raw 'x=1'
        """)
        #expect(
            CodeGenerator.generate(request, as: .curl)
                == "curl 'https://api.example.com/v1' -H 'Accept: */*' --compressed --data-raw 'x=1'"
        )
    }
}
