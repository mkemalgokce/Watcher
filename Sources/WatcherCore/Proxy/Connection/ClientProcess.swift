import Foundation

/// Finds which local program owns a client connection (the app that made a request), using `lsof`.
public enum ClientProcess {
    /// Name of the process whose end of a loopback TCP connection uses `port`; nil for remote clients or when lsof fails.
    public static func name(forLocalPort port: Int) -> String? {
        name(forLocalPort: port, runner: LiveCommandRunner.run)
    }

    static func name(forLocalPort port: Int, runner: CommandRunner) -> String? {
        let lsof = Command(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            // +c 0: full command names; -F: machine-readable fields (pid, command, name).
            arguments: ["-nP", "+c", "0", "-iTCP:\(port)", "-sTCP:ESTABLISHED", "-Fpcn"],
            // It runs for every new client connection, so a stuck lsof must not stall attribution.
            timeout: 5
        )
        guard let result = try? runner(lsof) else { return nil }
        return parse(result.text, port: port)
    }

    /// `lsof -F` output: `p<pid>` starts a process, `c<command>` names it, `n<local>-><remote>` describes a socket.
    static func parse(_ output: String, port: Int) -> String? {
        var command: String?
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": command = nil
            case "c": command = value
            case "n" where value.hasPrefix("127.0.0.1:\(port)->") || value.hasPrefix("[::1]:\(port)->"): return command
            default: break
            }
        }
        return nil
    }
}
