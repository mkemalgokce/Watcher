import ArgumentParser
import Foundation
import WatcherCore

struct Cert: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the root certificate path; trust it to decrypt HTTPS.")

    func run() throws {
        _ = try CertificateAuthority(directory: WatcherPaths.supportDirectory)
        print(WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem").path)
    }
}
