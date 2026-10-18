import Foundation
import WatcherTestSupport

/// One running `watcher-cli` with its own `WATCHER_HOME`, whose standard output the test can read while it runs.
final class WatcherCLIProcess {
    private let process = Process()
    private let output = LockedBox(Data())

    var printed: String {
        // swiftlint:disable:next optional_data_string_conversion
        String(decoding: output.value, as: UTF8.self)
    }

    var terminationStatus: Int32 {
        process.terminationStatus
    }

    init(binary: URL, arguments: [String], home: URL) {
        process.executableURL = binary
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["WATCHER_HOME": home.path]) { $1 }
        process.standardError = FileHandle.nullDevice
    }

    func run() throws {
        let pipe = Pipe()
        process.standardOutput = pipe
        pipe.fileHandleForReading.readabilityHandler = { [output] handle in
            let chunk = handle.availableData
            output.mutate { $0.append(chunk) }
        }
        try process.run()
    }

    /// The port from the `Watcher listening on 127.0.0.1:<port>` line, once the proxy has printed it.
    func listeningPort(timeout: TimeInterval = 30) async throws -> Int {
        let marker = "Watcher listening on 127.0.0.1:"
        guard await eventually(timeout: timeout, { printed.contains(marker) || !process.isRunning }),
              let line = printed.components(separatedBy: "\n").first(where: { $0.hasPrefix(marker) }),
              let port = Int(line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
        else { throw TestSupportError("watcher-cli did not report its port; it printed: \(printed)") }
        return port
    }

    /// Sends Ctrl-C, which makes `start` write its files and exit, and waits for it to finish.
    func interrupt(timeout: TimeInterval = 15) async throws {
        try await stop(with: SIGINT, timeout: timeout)
    }

    /// Sends `signal` and waits for the process to finish; one still running after `timeout` is killed.
    func stop(with signal: Int32, timeout: TimeInterval = 15) async throws {
        kill(process.processIdentifier, signal)
        guard await eventually(timeout: timeout, { !process.isRunning }) else {
            kill(process.processIdentifier, SIGKILL)
            throw TestSupportError("watcher-cli did not exit within \(timeout) s of signal \(signal)")
        }
    }

    deinit {
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
        }
    }
}
