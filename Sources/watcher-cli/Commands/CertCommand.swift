import ArgumentParser
import Foundation
import WatcherCore

struct Cert: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Print the root certificate path; trust it to decrypt HTTPS.")

    func run() throws {
        try run(in: .live)
    }

    func run(in environment: CLIEnvironment) throws {
        try environment.output(environment.certificateAuthority().certificateURL.path)
    }
}
