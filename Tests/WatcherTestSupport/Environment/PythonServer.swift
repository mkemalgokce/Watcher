import Foundation

/// A Python HTTP server running in the background until this object goes away. Its script binds 127.0.0.1:0 and
/// prints the port it got as its first line, so parallel tests never fight over a fixed number.
public final class PythonServer {
    public let port: Int
    private let process: Process

    /// `arguments` reach the script as `sys.argv[1...]`.
    public init(script: String, arguments: [String] = []) throws {
        let process = Process()
        process.executableURL = try ExternalTool.python3.require()
        process.arguments = ["-c", script] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw TestSupportError("python3 could not start: \(error)") }
        var line = Data()
        while let byte = try output.fileHandleForReading.read(upToCount: 1), !byte.isEmpty, byte != Data("\n".utf8) {
            line.append(byte)
        }
        // swiftlint:disable:next optional_data_string_conversion
        guard let port = Int(String(decoding: line, as: UTF8.self)) else {
            process.terminate()
            throw TestSupportError("the python server did not print its port")
        }
        self.port = port
        self.process = process
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public func waitUntilExit() {
        process.waitUntilExit()
    }

    deinit {
        if process.isRunning {
            process.terminate()
        }
    }
}
