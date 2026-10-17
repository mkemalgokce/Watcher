import ArgumentParser
import Foundation
import WatcherCore

struct SimulatorCert: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install-simulator-cert", abstract: "Trust the Watcher root certificate in an iOS Simulator.")

    @Option(help: "`booted`, `all` or a simulator UDID.") var device = "booted"

    func run() throws {
        let authority = try CertificateAuthority(directory: WatcherPaths.supportDirectory)
        _ = authority
        try SimulatorCertificate.install(certificate: WatcherPaths.supportDirectory.appendingPathComponent("watcher-ca.pem"), device: device)
        print("Installed in \(device)")
    }
}
