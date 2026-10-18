import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SystemProxyTests {
    // Never the real ~/.watcher backup: tests must not read or delete the user's saved proxy settings.
    private let directory: TemporaryDirectory
    private var backup: URL {
        directory.appending("system-proxy.json")
    }

    init() throws {
        directory = try TemporaryDirectory(prefix: "watcher-sp")
    }

    @Test
    func disableRestoresTheUsersOwnProxyInsteadOfSwitchingItOff() throws {
        // `networksetup` with one service that already has a web proxy of its own.
        let calls = LockedBox<[[String]]>([])
        let proxy = SystemProxy(run: { arguments in
            calls.mutate(arguments)
            switch arguments.first {
            case "-listallnetworkservices":
                return "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n"
            case "-getwebproxy":
                return "Enabled: Yes\nServer: corp-proxy.local\nPort: 3128\nAuthenticated Proxy Enabled: 0\n"
            case "-getsecurewebproxy":
                return "Enabled: No\nServer: 0.0.0.0\nPort: 0\nAuthenticated Proxy Enabled: 0\n"
            default: return ""
            }
        }, backupURL: backup)

        try proxy.enable(port: 9090)
        try proxy.enable(port: 9090) // a second enable must keep the real original
        let saved = try JSONDecoder().decode([String: SystemProxy.Original].self, from: Data(contentsOf: backup))
        #expect(saved["Wi-Fi"]?.web == .init(enabled: true, server: "corp-proxy.local", port: 3128))
        #expect(saved["Wi-Fi"]?.secure.enabled == false)

        calls.mutate { $0.removeAll() }
        try proxy.disable()
        #expect(calls.value.contains(["-setwebproxy", "Wi-Fi", "corp-proxy.local", "3128"]))
        #expect(calls.value.contains(["-setwebproxystate", "Wi-Fi", "on"]), "the user's proxy was on and stays on")
        #expect(calls.value.contains(["-setsecurewebproxystate", "Wi-Fi", "off"]))
        #expect(
            !calls.value.contains { $0.first == "-setsecurewebproxy" },
            "an empty original secure proxy has no host to write back"
        )
        #expect(!FileManager.default.fileExists(atPath: backup.path), "backup is consumed")

        // Without a backup (Watcher never enabled it) disabling just switches the proxies off.
        calls.mutate { $0.removeAll() }
        try proxy.disable()
        #expect(calls.value.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test
    func enableAndDisableTouchEnabledServicesOnly() throws {
        let calls = LockedBox<[[String]]>([])
        let proxy = SystemProxy(run: { arguments in
            calls.mutate(arguments)
            return arguments.first == "-listallnetworkservices"
                ? "An asterisk (*) denotes that a network service is disabled.\nWi-Fi\n*USB LAN\nThunderbolt Bridge\n"
                : ""
        }, backupURL: backup)
        try proxy.enable(port: 9090)
        #expect(calls.value.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "9090"]))
        #expect(calls.value.contains(["-setsecurewebproxy", "Thunderbolt Bridge", "127.0.0.1", "9090"]))
        #expect(!calls.value.contains { $0.contains("USB LAN") })
        try proxy.disable()
        #expect(calls.value.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test
    func parseHandlesMissingFields() {
        #expect(
            SystemProxy.parse("Enabled: Yes\nServer: h\nPort: 8080\n") == .init(enabled: true, server: "h", port: 8080)
        )
        #expect(SystemProxy.parse("") == .init(enabled: false, server: "", port: 0))
    }
}
