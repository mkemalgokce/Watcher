import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct FormFieldsTests {
    @Test
    func multipartFileKeepsItsBytes() {
        let png = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        var body = Data((
            "--B\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n"
                + "--B\r\nContent-Disposition: form-data; name=\"avatar\"; filename=\"a.png\"\r\n"
                + "Content-Type: image/png\r\n\r\n"
        ).utf8)
        body.append(png); body.append(Data("\r\n--B--\r\n".utf8))
        let request = RequestRecord.fixture(
            method: "POST",
            host: "h",
            path: "/up?x=1",
            headers: [Header("Content-Type", "multipart/form-data; boundary=B")],
            body: body
        )
        let fields = FormFields.parse(request)
        #expect(fields.map(\.name) == ["x", "title", "avatar"])
        #expect(fields[1].data == nil)
        #expect(fields[2].data == png); #expect(fields[2].contentType == "image/png")
        #expect(fields[2].filename == "a.png")
    }
}
