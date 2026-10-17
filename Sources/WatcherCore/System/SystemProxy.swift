import Foundation

/// Points macOS network services at Watcher and puts the user's own proxy settings back afterwards.
/// The original setting is saved before it is overridden, so a proxy the user already had is restored rather than merely
/// switched off.
public struct SystemProxy: Sendable {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    /// Runs `networksetup` with the given arguments and returns its output; replaceable so the command sequence can be tested.
    public typealias Runner = @Sendable ([String]) throws -> String

    /// A service's web proxy as it was before Watcher touched it.
    struct Original: Codable, Equatable {
        var web: Setting
        var secure: Setting
    }

    struct Setting: Codable, Equatable {
        var enabled: Bool
        var server: String
        var port: Int
    }

    private let run: Runner
    private let backupURL: URL

    public init(
        run: @escaping Runner = SystemProxy.networksetup,
        backupURL: URL = WatcherPaths.supportDirectory.appendingPathComponent("system-proxy-backup.json")
    ) {
        self.run = run; self.backupURL = backupURL
    }

    public static let shared = SystemProxy()

    /// True when an earlier run turned the system proxy on and never put the original back (crash, force quit).
    public var hasPendingRestore: Bool {
        FileManager.default.fileExists(atPath: backupURL.path)
    }

    public static func enable(host: String = "127.0.0.1", port: Int) throws {
        try shared.enable(host: host, port: port)
    }

    public static func disable() throws {
        try shared.disable()
    }

    public func enable(host: String = "127.0.0.1", port: Int) throws {
        let serviceNames = try services()
        // Enabling twice must not replace the real original with Watcher's own settings.
        if !FileManager.default.fileExists(atPath: backupURL.path) {
            try saveBackup(for: serviceNames)
        }
        for service in serviceNames {
            try run(["-setwebproxy", service, host, "\(port)"])
            try run(["-setsecurewebproxy", service, host, "\(port)"])
        }
    }

    public func disable() throws {
        let backup = loadBackup()
        for service in try services() {
            try restore(backup[service]?.web, for: service, set: "-setwebproxy", state: "-setwebproxystate")
            try restore(backup[service]?.secure, for: service, set: "-setsecurewebproxy", state: "-setsecurewebproxystate")
        }
        try? FileManager.default.removeItem(at: backupURL)
    }

    /// Enabled network services; the first output line is an explanatory note and disabled services start with `*`.
    public func services() throws -> [String] {
        try run(["-listallnetworkservices"]).split(separator: "\n").dropFirst().map(String.init).filter { !$0.hasPrefix("*") }
    }

    // MARK: Backup and restore

    private func saveBackup(for services: [String]) throws {
        var backup: [String: Original] = [:]
        for service in services {
            backup[service] = try Original(web: Self.parse(run(["-getwebproxy", service])), secure: Self.parse(run(["-getsecurewebproxy", service])))
        }
        try FileManager.default.createDirectory(at: backupURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(backup).write(to: backupURL, options: .atomic)
    }

    private func loadBackup() -> [String: Original] {
        (try? Data(contentsOf: backupURL)).flatMap { try? JSONDecoder().decode([String: Original].self, from: $0) } ?? [:]
    }

    /// Writes the saved host and port back; with no backup entry the proxy is simply switched off.
    private func restore(_ original: Setting?, for service: String, set: String, state: String) throws {
        guard let original else { try run([state, service, "off"]); return }
        if !original.server.isEmpty, original.port > 0 {
            try run([set, service, original.server, "\(original.port)"])
        }
        try run([state, service, original.enabled ? "on" : "off"])
    }

    /// `networksetup -getwebproxy` prints `Enabled: Yes`, `Server: host`, `Port: 8080`, ...
    static func parse(_ output: String) -> Setting {
        func value(_ key: String) -> String {
            output.split(separator: "\n").first { $0.hasPrefix("\(key):") }.map { $0.dropFirst(key.count + 1).trimmingCharacters(in: .whitespaces) } ?? ""
        }
        return Setting(enabled: value("Enabled").lowercased() == "yes", server: value("Server"), port: Int(value("Port")) ?? 0)
    }

    public static let networksetup: Runner = { arguments in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw Failure(description: "networksetup \(arguments.joined(separator: " ")): \(output)") }
        return output
    }
}
