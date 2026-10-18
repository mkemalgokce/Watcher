import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct HTTPMessageFileTests {
    @Test(arguments: ["\r\n", "\n"])
    func aRawMessageKeepsItsStatusHeadersAndBody(newline: String) {
        let text = ["HTTP/1.1 404 Not Found", "Content-Type: application/json", "X-Note:  spaced  ", "", #"{"e":1}"#]
            .joined(separator: newline)
        let response = HTTPMessageFile.response(from: Data(text.utf8), fileName: "mock.txt")
        #expect(response.status == 404)
        #expect(response.headers == [Header("Content-Type", "application/json"), Header("X-Note", "spaced")])
        #expect(response.body == Data(#"{"e":1}"#.utf8))
    }

    @Test(arguments: ["HTTP/1.1 OK\r\n\r\nbody", "HTTP/1.1\r\n\r\nbody", "HTTP/1.1 200 OK with no blank line"])
    func aMessageThatCannotBeReadIsServedAsAPlainBody(text: String) {
        let response = HTTPMessageFile.response(from: Data(text.utf8), fileName: "mock.txt")
        #expect(response.status == 200)
        #expect(response.body == Data(text.utf8))
        #expect(response.headers == [Header("Content-Type", "text/plain; charset=utf-8")])
    }

    @Test(arguments: [
        ("a.json", "application/json"), ("A.HTML", "text/html; charset=utf-8"), ("a.htm", "text/html; charset=utf-8"),
        ("a.js", "application/javascript"), ("a.jpeg", "image/jpeg"), ("a.svg", "image/svg+xml"),
        ("a.pdf", "application/pdf"), ("a", "application/octet-stream"), ("a.bin", "application/octet-stream"),
    ])
    func aPlainFileIsTypedByItsExtension(name: String, type: String) {
        #expect(HTTPMessageFile.mimeType(for: name) == type)
        let response = HTTPMessageFile.response(from: Data("x".utf8), fileName: name)
        #expect(response.headers.value(for: "Content-Type") == type)
    }
}
