import Foundation

/// Android emulators and phones reached through `adb`: list them, point them at the proxy, and put the certificate on them.
public struct AndroidDevice: Equatable, Identifiable, Sendable {
    public let serial: String
    public let model: String?
    public let isEmulator: Bool
    public var id: String {
        serial
    }

    public typealias Runner = @Sendable ([String]) throws -> String

    /// Parses `adb devices -l`; devices that are offline or unauthorised are left out.
    public static func parse(_ output: String) -> [AndroidDevice] {
        output.split(separator: "\n").dropFirst().compactMap { line in
            let fields = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard fields.count >= 2, fields[1] == "device" else { return nil }
            let model = fields.first { $0.hasPrefix("model:") }.map { String($0.dropFirst(6)) }
            return AndroidDevice(serial: fields[0], model: model, isEmulator: fields[0].hasPrefix("emulator-"))
        }
    }

    public static func list(run: Runner = adb) throws -> [AndroidDevice] {
        try parse(run(["devices", "-l"]))
    }

    /// Copies the certificate to Downloads, where Settings → Install a certificate can pick it up.
    public func pushCertificate(_ certificate: URL, run: Runner = adb) throws {
        _ = try run(["-s", serial, "push", certificate.path, "/sdcard/Download/watcher-ca.cer"])
    }

    /// Sets (or with nil clears) the global HTTP proxy; `host:port` as the device sees the Mac (`10.0.2.2` on the emulator).
    public func setProxy(_ endpoint: String?, run: Runner = adb) throws {
        _ = try run(["-s", serial, "shell", "settings", "put", "global", "http_proxy", endpoint ?? ":0"])
    }

    public func proxyEndpoint(port: Int, lanAddress: String?) -> String? {
        isEmulator ? "10.0.2.2:\(port)" : lanAddress.map { "\($0):\(port)" }
    }

    public static let adb: Runner = adb(
        using: LiveCommandRunner.run,
        isExecutable: FileAccess.live.isExecutable,
        home: NSHomeDirectory()
    )

    static func adb(
        using runner: @escaping CommandRunner,
        isExecutable: @escaping @Sendable (String) -> Bool,
        home: String
    ) -> Runner {
        let candidates = [
            "/opt/homebrew/bin/adb", "/usr/local/bin/adb", "\(home)/Library/Android/sdk/platform-tools/adb",
        ]
        return { arguments in
            guard let path = candidates.first(where: isExecutable) else {
                throw CommandFailure(
                    description: "adb not found. Install Android platform-tools (brew install android-platform-tools)."
                )
            }
            return try Command(executable: URL(fileURLWithPath: path), arguments: arguments, mergesErrorOutput: true)
                .checkedOutput(using: runner)
        }
    }
}
