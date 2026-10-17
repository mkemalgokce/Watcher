@testable import WatcherCore
import XCTest

/// What Compose sends, checked by a server that is not ours: Python's standard library parses the bodies.
final class ComposeEndToEndTests: XCTestCase {
    /// A one-shot Python server: prints its port, parses one POST (multipart or urlencoded) and answers with what it understood.
    private func startParsingServer() throws -> (Process, Int) {
        let script = #"""
        import sys, http.server, email.parser, email.policy, urllib.parse
        class H(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                ctype = self.headers['Content-Type']
                out = []
                if ctype.startswith('multipart/form-data'):
                    msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(b'Content-Type: ' + ctype.encode() + b'\r\n\r\n' + body)
                    for part in msg.iter_parts():
                        name = part.get_param('name', header='content-disposition')
                        filename = part.get_filename()
                        data = part.get_payload(decode=True)
                        out.append(f"{name}={filename}:{len(data)}:{part.get_content_type()}" if filename else f"{name}={data.decode()}")
                else:
                    out = [f"{k}={v[0]}" for k, v in urllib.parse.parse_qs(body.decode()).items()]
                reply = ";".join(out).encode()
                self.send_response(200); self.send_header('Content-Length', str(len(reply))); self.end_headers(); self.wfile.write(reply)
            def log_message(self, *a): pass
        s = http.server.HTTPServer(('127.0.0.1', 0), H)
        print(s.server_address[1], flush=True)
        s.handle_request()
        """#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); process.arguments = ["-c", script]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw XCTSkip("python3 unavailable") }
        var line = Data()
        while let byte = try pipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data("\n".utf8) {
            line.append(byte)
        }
        guard let port = Int(String(decoding: line, as: UTF8.self)) else { throw XCTSkip("python server did not start") }
        return (process, port)
    }

    func testMultipartWithAFileReachesARealServerIntact() async throws {
        let harness = try Harness(); try await harness.start()
        let (server, port) = try startParsingServer()
        let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A])
        let boundary = RequestBodyBuilder.newBoundary()
        let body = RequestBodyBuilder.multipart([
            KeyValue("title", "Holiday photo"),
            KeyValue("photo", "", file: .init(filename: "red.png", contentType: "image/png", data: png)),
            KeyValue("draft", "yes", isEnabled: false),
        ], boundary: boundary)
        let request = try RequestRecord(
            method: "POST",
            scheme: "http",
            host: "127.0.0.1",
            port: port,
            path: "/upload",
            headers: [Header("Content-Type", XCTUnwrap(RequestBodyBuilder.contentType(for: .multipart, boundary: boundary)))],
            body: body
        )
        let response = await harness.engine.send(request)
        server.waitUntilExit()
        XCTAssertEqual(response.status, 200)
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "title=Holiday photo;photo=red.png:7:image/png")
        await harness.stop()
    }

    func testURLEncodedFormReachesARealServerIntact() async throws {
        let harness = try Harness(); try await harness.start()
        let (server, port) = try startParsingServer()
        let request = RequestRecord(
            method: "POST",
            scheme: "http",
            host: "127.0.0.1",
            port: port,
            path: "/form",
            headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
            body: RequestBodyBuilder.urlEncoded([KeyValue("q", "a b&c"), KeyValue("lang", "tr")])
        )
        let response = await harness.engine.send(request)
        server.waitUntilExit()
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "q=a b&c;lang=tr")
        await harness.stop()
    }
}
