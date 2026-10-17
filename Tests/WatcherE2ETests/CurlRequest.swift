import Foundation
import WatcherTestSupport

/// `curl` sending one request through an HTTP proxy, ignoring any proxy settings in the environment.
enum CurlRequest {
    static func get(_ url: String, throughProxyPort port: Int) throws -> String {
        let process = Process()
        process.executableURL = try ExternalTool.curl.require()
        process.arguments = [
            "--silent", "--show-error", "--max-time", "10",
            "--noproxy", "", "--proxy", "http://127.0.0.1:\(port)", url,
        ]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw TestSupportError("curl exited with \(process.terminationStatus)")
        }
        // swiftlint:disable:next optional_data_string_conversion
        return String(decoding: data, as: UTF8.self)
    }
}
