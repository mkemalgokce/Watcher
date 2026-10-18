import ArgumentParser
import Foundation
import WatcherCore

struct SimulatorCert: ParsableCommand {
    static let configuration = CommandConfiguration(commandName: "install-simulator-cert", abstract: "Trust the Watcher root certificate in an iOS Simulator.")

    @Option(help: "`booted`, `all` or a simulator UDID.") var device = "booted"

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        let certificate = try environment.certificateAuthority().certificateURL
        try SimulatorCertificate.install(certificate: certificate, device: device, run: environment.xcrun)
        environment.output("Installed in \(device)")
    }
}
