import Darwin
import Foundation

/// Finds which local program owns a client connection (the app that made a request), using `lsof`.
public enum ClientProcess {
    /// The process behind one end of a connection.
    struct Owner: Equatable {
        let pid: Int32
        let command: String
    }

    /// Who owns the local TCP connection whose client end uses `port`; nil for remote clients or when lsof fails.
    public static func identity(forLocalPort port: Int) -> ClientIdentity? {
        identity(forLocalPort: port, runner: LiveCommandRunner.run, executablePath: executablePath(ofPid:))
    }

    static func identity(
        forLocalPort port: Int,
        runner: CommandRunner,
        executablePath: (Int32) -> String?
    ) -> ClientIdentity? {
        let lsof = Command(
            executable: URL(fileURLWithPath: "/usr/sbin/lsof"),
            // +c 0: full command names; -F: machine-readable fields (pid, command, name).
            arguments: ["-nP", "+c", "0", "-iTCP:\(port)", "-sTCP:ESTABLISHED", "-Fpcn"],
            // It runs for every new client connection, so a stuck lsof must not stall attribution.
            timeout: 5
        )
        guard let result = try? runner(lsof), let owner = parse(result.text, port: port) else { return nil }
        return .classify(process: owner.command, executablePath: executablePath(owner.pid))
    }

    /// `lsof -F` output: `p<pid>` starts a process, `c<command>` names it, `n<local>-><remote>` describes a socket.
    static func parse(_ output: String, port: Int) -> Owner? {
        var pid: Int32?
        var command: String?
        for line in output.split(separator: "\n") {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": pid = Int32(value); command = nil
            case "c": command = value
            case "n" where Self.isClientEnd(value, port: port):
                guard let pid, let command else { return nil }
                return Owner(pid: pid, command: command)
            default: break
            }
        }
        return nil
    }

    /// The client end of a connection reads `<address>:<port>-><server>`, whatever address (loopback or the Mac's own LAN one) it used.
    private static func isClientEnd(_ name: String, port: Int) -> Bool {
        guard let arrow = name.range(of: "->") else { return false }
        return name[..<arrow.lowerBound].hasSuffix(":\(port)")
    }

    /// The executable's path through libproc; nil when the process is gone or protected (privileged daemons).
    static func executablePath(ofPid pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }
}
