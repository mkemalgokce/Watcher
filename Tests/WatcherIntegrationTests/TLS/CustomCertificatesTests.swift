import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.timeLimit(.minutes(1)), .tags(.integration, .network, .externalTool))
struct CustomCertificatesTests {
    private let directory: TemporaryDirectory

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-p12")
    }

    @Test(
        .enabled(if: ExternalTool.openssl.isAvailable, "needs openssl"),
        .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
    )
    func aCustomServerCertificateIsPresentedInsteadOfAGeneratedOne() async throws {
        let rule = try pinnedServerRule()
        #expect(throws: Never.self) { try CustomCertificates.serverContext(rule) }
        var wrong = rule; wrong.passphrase = "nope"
        #expect(throws: (any Error).self) { try CustomCertificates.serverContext(wrong) }

        let output = try await withHarness(configure: {
            $0.customCertificates = RuleSet(isEnabled: true, rules: [rule])
        }) { harness in
            try runPython(certificatesPresented(port: harness.proxyPort)).components(separatedBy: "\n")
        }
        let pinned = try subjectAndIssuer(#require(output.first { $0.hasPrefix("pinned.test") }))
        let other = try subjectAndIssuer(#require(output.first { $0.hasPrefix("other.test") }))
        #expect(pinned.contains("CN=pinned.test") && !pinned.contains("Watcher Root CA"), "\(pinned)")
        #expect(other.contains("Watcher Root CA"), "\(other)")
    }

    @Test(
        .enabled(if: ExternalTool.openssl.isAvailable, "needs openssl"),
        .enabled(if: ExternalTool.python3.isAvailable, "needs python3")
    )
    func aCustomServerCertificateDecryptsWithoutAWatcherAuthorityOverConnectAndSocks() async throws {
        let server = ProxyServer(authority: nil, clientApp: { _ in nil }, localAddresses: { [] })
        let rule = try pinnedServerRule()
        server.updateUpstream(external: ExternalProxySettings(), pac: nil, dnsRules: [], certificates: [rule])
        let socksPort = try freeLoopbackPort()
        do {
            let proxyPort = try await server.start(port: 0)
            #expect(await server.setSocks(SocksSettings(isEnabled: true, port: socksPort), host: "127.0.0.1") == nil)
            let script = handshakes(proxyPort: proxyPort, socksPort: socksPort)
            let output = try runPython(script).components(separatedBy: "\n")
            for route in ["connect", "socks"] {
                let line = try #require(output.first { $0.hasPrefix(route) }, "\(output)")
                #expect(try subjectAndIssuer(line).contains("CN=pinned.test"), "\(route)")
            }
        } catch {
            try? await server.stop()
            throw error
        }
        try await server.stop()
    }

    /// A server rule for `pinned.test` backed by a fresh self-signed P12.
    private func pinnedServerRule() throws -> CustomCertificateRule {
        let key = directory.appending("k.pem").path, cert = directory.appending("c.pem").path
        let p12 = directory.appending("id.p12").path
        try openssl([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
            "-subj", "/CN=pinned.test", "-days", "2",
        ])
        try openssl(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "pass:secret"])
        return CustomCertificateRule(host: "pinned.test", role: .server, p12Path: p12, passphrase: "secret")
    }

    private func openssl(_ arguments: [String]) throws {
        guard try ExternalTool.openssl.run(arguments).status == 0 else {
            throw TestSupportError("openssl \(arguments[0]) failed")
        }
    }

    /// Handshakes through the proxy for two hosts and prints each host with the certificate that came back.
    private func certificatesPresented(port: Int) -> String {
        """
        import socket, ssl, sys
        for host in ("pinned.test", "other.test"):
            s = socket.create_connection(("127.0.0.1", \(port)), timeout=10)
            s.sendall(f"CONNECT {host}:443 HTTP/1.1\\r\\nHost: {host}:443\\r\\n\\r\\n".encode()); s.recv(4096)
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
            der = ctx.wrap_socket(s, server_hostname=host).getpeercert(binary_form=True)
            print(host, ssl.DER_cert_to_PEM_cert(der).replace("\\n", "|"))
        """
    }

    /// Handshakes for `pinned.test` once after an HTTP CONNECT and once after a SOCKS5 connect, printing each certificate.
    private func handshakes(proxyPort: Int, socksPort: Int) -> String {
        """
        import socket, ssl
        def show(route, s):
            ctx = ssl.create_default_context(); ctx.check_hostname = False; ctx.verify_mode = ssl.CERT_NONE
            der = ctx.wrap_socket(s, server_hostname="pinned.test").getpeercert(binary_form=True)
            print(route, ssl.DER_cert_to_PEM_cert(der).replace("\\n", "|"))
        s = socket.create_connection(("127.0.0.1", \(proxyPort)), timeout=10)
        s.sendall(b"CONNECT pinned.test:443 HTTP/1.1\\r\\nHost: pinned.test:443\\r\\n\\r\\n"); s.recv(4096)
        show("connect", s)
        s = socket.create_connection(("127.0.0.1", \(socksPort)), timeout=10)
        s.sendall(bytes([5, 1, 0])); s.recv(2)
        s.sendall(bytes([5, 1, 0, 3, 11]) + b"pinned.test" + bytes([1, 187])); s.recv(10)
        show("socks", s)
        """
    }

    private func subjectAndIssuer(_ line: String) throws -> String {
        let pem = line.split(separator: " ", maxSplits: 1)[1].replacingOccurrences(of: "|", with: "\n")
        return try ExternalTool.openssl.run(["x509", "-noout", "-subject", "-issuer"], input: Data(pem.utf8)).text
    }
}
