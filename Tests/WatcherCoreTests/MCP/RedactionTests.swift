import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RedactionTests {
    @Test
    func hidesSecretsOnlyInSecretHeaders() {
        let headers = Redaction.redact([
            Header("Authorization", "Bearer abc"),
            Header("cookie", "sid=1"),
            Header("Accept", "*/*"),
            Header("X-Api-Key", "k"),
        ])
        #expect(headers.map(\.value) == ["[redacted]", "[redacted]", "*/*", "[redacted]"])
        #expect(headers.map(\.name) == ["Authorization", "cookie", "Accept", "X-Api-Key"])
    }
}
