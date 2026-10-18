import Foundation
import WatcherCore

/// Everything a command reaches outside the process through: `run()` passes `.live`, tests their doubles.
struct CLIEnvironment {
    /// Writes one line to standard output.
    var output: @Sendable (String) -> Void
    /// Writes one line to standard error.
    var errorOutput: @Sendable (String) -> Void
    /// The next line of standard input without its newline; nil at its end.
    var readLine: @Sendable () -> String?
    var variables: [String: String]
    var home: URL
    var files: FileAccess
    var commands: CommandRunner
    var lanAddresses: @Sendable () -> [LocalNetwork.Address]
    /// Opens the engine whose settings, root certificate and workspaces live in the given folder.
    var makeEngine: @Sendable (URL) throws -> any EngineControlling
    var shutdownSignal: ShutdownSignal
    var now: @Sendable () -> Date

    var supportDirectory: URL {
        WatcherPaths.directory(environment: variables, home: home)
    }

    var settings: SettingsStore {
        SettingsStore(url: WatcherPaths.settingsFile(in: supportDirectory), files: files, now: now)
    }

    var systemProxy: SystemProxy {
        SystemProxy(
            run: SystemProxy.networksetup(using: commands),
            backupURL: WatcherPaths.systemProxyBackupFile(in: supportDirectory),
            files: files
        )
    }

    var adb: AndroidDevice.Runner {
        AndroidDevice.adb(using: commands, isExecutable: files.isExecutable, home: home.path)
    }

    var xcrun: SimulatorCertificate.Runner {
        SimulatorCertificate.xcrun(using: commands)
    }

    /// Loads the root certificate, creating it on first use.
    func certificateAuthority() throws -> CertificateAuthority {
        try CertificateAuthority(directory: supportDirectory, files: files, now: now)
    }

    /// Opens the engine on the support folder with its log going to `log`, and starts the proxy on `port` (or the
    /// stored one).
    func startEngine(
        port: Int?,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> (engine: any EngineControlling, port: Int) {
        let engine = try makeEngine(supportDirectory)
        engine.onLog = log
        return try await (engine, engine.start(port: port))
    }

    /// A path the user typed; `~` is their home folder.
    func url(forPath path: String) -> URL {
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
