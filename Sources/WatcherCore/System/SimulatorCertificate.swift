import Foundation

/// Installs the Watcher root certificate into an iOS Simulator's keychain.
public enum SimulatorCertificate {
    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public typealias Runner = @Sendable ([String]) throws -> String

    /// `device` is `booted`, `all` or a simulator UDID.
    public static func install(certificate: URL, device: String = "booted", run: Runner = xcrun) throws {
        // The value goes to simctl as an argument (no shell), but only the known shapes make sense.
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        guard !device.isEmpty, device.unicodeScalars.allSatisfy(allowed.contains) else { throw Failure(description: "Invalid simulator: \(device)") }
        _ = try run(["simctl", "keychain", device, "add-root-cert", certificate.path])
    }

    public struct Simulator: Equatable, Identifiable, Sendable {
        public let udid: String
        public let name: String
        public let runtime: String
        public let isBooted: Bool
        public var id: String {
            udid
        }
    }

    /// Available simulators from `simctl list devices --json`, booted first.
    public static func simulators(run: Runner = xcrun) throws -> [Simulator] {
        struct Listing: Decodable {
            struct Device: Decodable { let udid: String; let name: String; let state: String; let isAvailable: Bool? }
            let devices: [String: [Device]]
        }
        let listing = try JSONDecoder().decode(Listing.self, from: Data(run(["simctl", "list", "devices", "--json"]).utf8))
        let all = listing.devices.flatMap { runtime, devices in
            devices.filter { $0.isAvailable ?? true }.map {
                Simulator(udid: $0.udid, name: $0.name, runtime: runtimeName(runtime), isBooted: $0.state == "Booted")
            }
        }
        return all.sorted { ($0.isBooted ? 0 : 1, $0.runtime, $0.name) < ($1.isBooted ? 0 : 1, $1.runtime, $1.name) }
    }

    /// `com.apple.CoreSimulator.SimRuntime.iOS-17-5` -> `iOS 17.5`
    static func runtimeName(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = tail.split(separator: "-")
        guard let platform = parts.first else { return tail }
        return ([String(platform)] + [parts.dropFirst().joined(separator: ".")]).filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static let xcrun: Runner = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "xcrun \(arguments.joined(separator: " ")): \(output)") }
        return output
    }
}
