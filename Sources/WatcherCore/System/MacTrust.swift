import Foundation

/// Trusts the Watcher root certificate in the current user's login keychain, so Safari and other Mac apps accept decrypted HTTPS.
public struct MacTrust: Sendable {
    public typealias Runner = @Sendable (_ launchPath: String, _ arguments: [String]) throws -> (status: Int32, output: String)

    private let run: Runner
    private let keychain: String
    public static let certificateName = "Watcher Root CA"

    public init(keychain: String = "\(NSHomeDirectory())/Library/Keychains/login.keychain-db", run: @escaping Runner = MacTrust.process) {
        self.keychain = keychain; self.run = run
    }

    /// Whether a certificate with Watcher's name is in the keychain (it can still be untrusted).
    public func isInstalled() -> Bool {
        ((try? run("/usr/bin/security", ["find-certificate", "-c", Self.certificateName, keychain]))?.status ?? 1) == 0
    }

    /// Asks macOS to trust the certificate as a root for SSL; macOS shows its own password prompt.
    public func install(certificate: URL) throws {
        let result = try run("/usr/bin/security", ["add-trusted-cert", "-r", "trustRoot", "-k", keychain, certificate.path])
        guard result.status == 0 else { throw SimulatorCertificate.Failure(description: "security add-trusted-cert: \(result.output)") }
    }

    public func remove() throws {
        let result = try run("/usr/bin/security", ["delete-certificate", "-c", Self.certificateName, keychain])
        guard result.status == 0 else { throw SimulatorCertificate.Failure(description: "security delete-certificate: \(result.output)") }
    }

    public static let process: Runner = { launchPath, arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return (process.terminationStatus, output)
    }
}
