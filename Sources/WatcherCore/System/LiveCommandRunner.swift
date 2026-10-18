import Foundation

public enum LiveCommandRunner {
    public static let run: CommandRunner = { command in
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments
        if let environment = command.environment {
            process.environment = environment
        }
        let input = Pipe(), output = Pipe()
        if command.input != nil {
            process.standardInput = input
        }
        process.standardOutput = output
        process.standardError = command.mergesErrorOutput ? output : FileHandle.nullDevice
        try process.run()

        let killer = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        if let timeout = command.timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        }
        if let data = command.input {
            let writer = input.fileHandleForWriting
            _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1) // a program exiting unread must not kill this process
            DispatchQueue.global().async { // alongside the read below, so neither side waits on a full pipe
                try? writer.write(contentsOf: data)
                try? writer.close()
            }
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        return CommandResult(status: process.terminationStatus, output: data)
    }
}
