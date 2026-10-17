import Foundation

/// Finds which local program owns a client connection (the app that made a request), using `lsof`.
public enum ClientProcess {
    /// Name of the process whose end of a loopback TCP connection uses `port`; nil for remote clients or when lsof fails.
    public static func name(forLocalPort port: Int) -> String? {
        name(forLocalPort: port, lsof: runLsof(port:))
    }

    static func name(forLocalPort port: Int, lsof: (Int) -> String?) -> String? {
        guard let output = lsof(port) else { return nil }
        return parse(output, port: port)
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

    private static func runLsof(port: Int) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        // +c 0: full command names; -F: machine-readable fields (pid, command, name).
        process.arguments = ["-nP", "+c", "0", "-iTCP:\(port)", "-sTCP:ESTABLISHED", "-Fpcn"]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        return output
    }
}
