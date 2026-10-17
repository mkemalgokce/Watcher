import Foundation

/// Filters JSON with the `jq` program when it is installed.
public enum JQ {
    private static let candidates = ["/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq"]

    public static var executable: URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Programs that start like a jq filter (`.users[] | .name`) rather than the simple path syntax of `JSONQuery`.
    public static func looksLikeJQ(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(".") || trimmed.contains("|") || trimmed.hasPrefix("map(") || trimmed.hasPrefix("select(")
    }

    /// jq's output, or nil when jq is missing, the query is rejected or it takes longer than `timeout`.
    public static func run(_ query: String, on json: Data, timeout: TimeInterval = 5) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // A leading dash would be read as a jq option; the empty environment keeps `$ENV` from exposing this process's variables.
        guard let executable, !trimmed.isEmpty, !trimmed.hasPrefix("-") else { return nil }
        let process = Process()
        process.executableURL = executable
        process.arguments = ["-M", trimmed]
        process.environment = [:]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }

        let killer = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        input.fileHandleForWriting.write(json)
        input.fileHandleForWriting.closeFile()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}
