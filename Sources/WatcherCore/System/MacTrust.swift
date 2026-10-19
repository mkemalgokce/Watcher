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

    /// Whether macOS trusts this certificate file; a root of the same name from an older install does not count.
    public func isTrusted(certificate: URL) -> Bool {
        let arguments = ["verify-cert", "-c", certificate.path, "-p", "basic", "-L", "-l"]
        return ((try? run("/usr/bin/security", arguments))?.status ?? 1) == 0
    }

    /// Asks macOS to trust the certificate as a root for SSL; macOS shows its own password prompt.
    public func install(certificate: URL) throws {
        let result = try run("/usr/bin/security", ["add-trusted-cert", "-r", "trustRoot", "-k", keychain, certificate.path])
        guard result.status == 0 else {
            throw CommandFailure(description: "security add-trusted-cert: \(result.output)")
        }
    }

    public func remove() throws {
        let result = try run("/usr/bin/security", ["delete-certificate", "-c", Self.certificateName, keychain])
        guard result.status == 0 else {
            throw CommandFailure(description: "security delete-certificate: \(result.output)")
        }
    }

    public static let process: Runner = process(using: LiveCommandRunner.run)

    static func process(using runner: @escaping CommandRunner) -> Runner {
        { launchPath, arguments in
            let executable = URL(fileURLWithPath: launchPath)
            let result = try runner(Command(executable: executable, arguments: arguments, mergesErrorOutput: true))
            return (result.status, result.text)
        }
    }
}
