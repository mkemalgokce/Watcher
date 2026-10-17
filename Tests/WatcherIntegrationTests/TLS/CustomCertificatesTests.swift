import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.integration, .network, .externalTool))
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
        let key = directory.appending("k.pem").path, cert = directory.appending("c.pem").path
        let p12 = directory.appending("id.p12").path
        try openssl([
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", key, "-out", cert,
            "-subj", "/CN=pinned.test", "-days", "2",
        ])
        try openssl(["pkcs12", "-export", "-inkey", key, "-in", cert, "-out", p12, "-passout", "pass:secret"])

        let rule = CustomCertificateRule(host: "pinned.test", role: .server, p12Path: p12, passphrase: "secret")
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

    private func openssl(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = try ExternalTool.openssl.require()
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw TestSupportError("openssl \(arguments[0]) failed") }
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

    private func subjectAndIssuer(_ line: String) throws -> String {
        let pem = line.split(separator: " ", maxSplits: 1)[1].replacingOccurrences(of: "|", with: "\n")
        let tool = Process()
        tool.executableURL = try ExternalTool.openssl.require()
        tool.arguments = ["x509", "-noout", "-subject", "-issuer"]
        let input = Pipe(), out = Pipe(); tool.standardInput = input; tool.standardOutput = out
        try tool.run()
        input.fileHandleForWriting.write(Data(pem.utf8)); input.fileHandleForWriting.closeFile()
        tool.waitUntilExit()
        return String(bytes: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }
}
