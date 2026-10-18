import ArgumentParser
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
    /// What a relative path typed on the command line is relative to.
    var currentDirectory: URL
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
    /// stored one), decrypting HTTPS only when `decryptsHTTPS`. A failure is written to standard error and ends the
    /// command with a failure exit code.
    func startEngine(
        port: Int?,
        decryptsHTTPS: Bool = true,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> (engine: any EngineControlling, port: Int) {
        let engine: any EngineControlling
        do { engine = try makeEngine(supportDirectory) } catch {
            let folder = supportDirectory.path
            errorOutput("Cannot open Watcher's data in \(folder): \(error). Check the folder is readable.")
            throw ExitCode.failure
        }
        engine.onLog = log
        engine.decryptsHTTPS = decryptsHTTPS
        do { return try await (engine, engine.start(port: port)) } catch {
            errorOutput("Cannot start the proxy: \(error). Another program may be using the port; try --port.")
            throw ExitCode.failure
        }
    }

    /// Puts back the system proxy a crashed `--system-proxy` session left pointing at Watcher, telling `report`.
    func restoreLeftoverSystemProxy(report: (String) -> Void) {
        let proxy = systemProxy
        guard proxy.hasPendingRestore, (try? proxy.disable()) != nil else { return }
        report("Put back the system proxy a previous session left pointing at Watcher")
    }

    /// A path the user typed; `~` is their home folder, and a relative one starts at the working directory.
    func url(forPath path: String) -> URL {
        if path == "~" {
            return home
        }
        if path.hasPrefix("~/") {
            return home.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path, relativeTo: currentDirectory).absoluteURL.standardized
    }
}
