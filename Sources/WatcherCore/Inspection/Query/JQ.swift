import Foundation

/// Filters JSON with the `jq` program when it is installed.
public enum JQ {
    private static let candidates = ["/opt/homebrew/bin/jq", "/usr/local/bin/jq", "/usr/bin/jq"]

    public static func executable(isExecutable: (String) -> Bool = FileAccess.live.isExecutable) -> URL? {
        candidates.first(where: isExecutable).map(URL.init(fileURLWithPath:))
    }

    /// Programs that start like a jq filter (`.users[] | .name`) rather than the simple path syntax of `JSONQuery`.
    public static func looksLikeJQ(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix(".") || trimmed.contains("|") || trimmed.hasPrefix("map(") || trimmed.hasPrefix("select(")
    }

    /// jq's output, or nil when jq is missing, the query is rejected or it takes longer than `timeout`.
    public static func run(
        _ query: String,
        on json: Data,
        timeout: TimeInterval = 5,
        runner: CommandRunner = LiveCommandRunner.run,
        isExecutable: (String) -> Bool = FileAccess.live.isExecutable
    ) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        // A leading dash would be read as a jq option; the empty environment keeps `$ENV` from exposing this process's variables.
        guard !trimmed.isEmpty, !trimmed.hasPrefix("-"), let executable = executable(isExecutable: isExecutable) else {
            return nil
        }
        let command = Command(
            executable: executable,
            arguments: ["-M", trimmed],
            environment: [:],
            input: json,
            timeout: timeout
        )
        guard let result = try? runner(command), result.status == 0 else { return nil }
        return result.text
    }
}
