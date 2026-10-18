import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension WatcherEngineTests {
    /// What Compose sends and how it answers; the form bodies are checked by a server that is not ours, Python's standard
    /// library.
    @Suite(.serialized)
    struct Compose {
        @Test(.tags(.timing))
        func aSilentServerIsAnsweredWith502AfterTheTimeout() async throws {
            let silent = SilentOrigin()
            try await silent.start()
            do {
                try await withHarness { harness in
                    let started = Date()
                    let response = await harness.engine.send(
                        .fixture(scheme: "http", host: "127.0.0.1", port: silent.port),
                        timeout: 1
                    )
                    #expect(response.status == 502)
                    #expect(Date().timeIntervalSince(started) < 30)
                }
            } catch {
                await silent.stop()
                throw error
            }
            await silent.stop()
        }

        @Test
        func redirectsAreFollowedOnRequestAndEachHopIsRecorded() async throws {
            try await withHarness { harness in
                let request = RequestRecord.fixture(
                    scheme: "http",
                    host: "upstream.test",
                    port: harness.upstream.port,
                    path: "/redirect"
                )
                let plain = await harness.engine.send(request)
                #expect(plain.status == 302)
                let followed = await harness.engine.send(request, followRedirects: true)
                #expect(String(bytes: followed.body, encoding: .utf8)?.hasPrefix("GET /final") == true)
                #expect(harness.engine.store.all.map(\.request.path) == ["/redirect", "/redirect", "/final"])
            }
        }

        @Test(.enabled(if: ExternalTool.python3.isAvailable, "needs python3"), .tags(.externalTool))
        func multipartWithAFileReachesARealServerIntact() async throws {
            try await withHarness { harness in
                let server = try PythonServer(script: Self.parsingServer)
                let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A])
                let boundary = RequestBodyBuilder.newBoundary()
                let body = RequestBodyBuilder.multipart([
                    KeyValue("title", "Holiday photo"),
                    KeyValue("photo", "", file: .init(filename: "red.png", contentType: "image/png", data: png)),
                    KeyValue("draft", "yes", isEnabled: false),
                ], boundary: boundary)
                let contentType = try #require(RequestBodyBuilder.contentType(for: .multipart, boundary: boundary))
                let response = await harness.engine.send(.fixture(
                    method: "POST",
                    scheme: "http",
                    host: "127.0.0.1",
                    port: server.port,
                    path: "/upload",
                    headers: [Header("Content-Type", contentType)],
                    body: body
                ))
                try await server.waitUntilExit()
                #expect(response.status == 200)
                #expect(
                    String(bytes: response.body, encoding: .utf8) == "title=Holiday photo;photo=red.png:7:image/png"
                )
            }
        }

        @Test(.enabled(if: ExternalTool.python3.isAvailable, "needs python3"), .tags(.externalTool))
        func aURLEncodedFormReachesARealServerIntact() async throws {
            try await withHarness { harness in
                let server = try PythonServer(script: Self.parsingServer)
                let response = await harness.engine.send(.fixture(
                    method: "POST",
                    scheme: "http",
                    host: "127.0.0.1",
                    port: server.port,
                    path: "/form",
                    headers: [Header("Content-Type", "application/x-www-form-urlencoded")],
                    body: RequestBodyBuilder.urlEncoded([KeyValue("q", "a b&c"), KeyValue("lang", "tr")])
                ))
                try await server.waitUntilExit()
                #expect(String(bytes: response.body, encoding: .utf8) == "q=a b&c;lang=tr")
            }
        }

        /// A one-shot Python server: prints its port, parses one POST (multipart or urlencoded) and answers with what it
        /// understood.
        private static let parsingServer = #"""
        import sys, http.server, email.parser, email.policy, urllib.parse
        class H(http.server.BaseHTTPRequestHandler):
            def do_POST(self):
                body = self.rfile.read(int(self.headers['Content-Length']))
                ctype = self.headers['Content-Type']
                out = []
                if ctype.startswith('multipart/form-data'):
                    msg = email.parser.BytesParser(policy=email.policy.default).parsebytes(
                        b'Content-Type: ' + ctype.encode() + b'\r\n\r\n' + body)
                    for part in msg.iter_parts():
                        name = part.get_param('name', header='content-disposition')
                        filename = part.get_filename()
                        data = part.get_payload(decode=True)
                        out.append(
                            f"{name}={filename}:{len(data)}:{part.get_content_type()}" if filename
                            else f"{name}={data.decode()}")
                else:
                    out = [f"{k}={v[0]}" for k, v in urllib.parse.parse_qs(body.decode()).items()]
                reply = ";".join(out).encode()
                self.send_response(200); self.send_header('Content-Length', str(len(reply)))
                self.end_headers(); self.wfile.write(reply)
            def log_message(self, *a): pass
        s = http.server.HTTPServer(('127.0.0.1', 0), H)
        print(s.server_address[1], flush=True)
        s.handle_request()
        """#
    }
}
