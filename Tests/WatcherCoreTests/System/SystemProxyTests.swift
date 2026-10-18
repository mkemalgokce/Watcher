import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SystemProxyTests {
    // Never the real ~/.watcher backup: tests must not read or delete the user's saved proxy settings.
    private let backup = URL(fileURLWithPath: "/fake-home/.watcher/system-proxy.json")
    private let files = FileAccessFake()

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
        }, backupURL: backup, files: files.access)

        try proxy.enable(port: 9090)
        try proxy.enable(port: 9090) // a second enable must keep the real original
        let saved = try JSONDecoder().decode(
            [String: SystemProxy.Original].self,
            from: #require(files.contents(of: backup.path))
        )
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
        #expect(files.contents(of: backup.path) == nil, "backup is consumed")

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
        }, backupURL: backup, files: files.access)
        try proxy.enable(port: 9090)
        #expect(calls.value.contains(["-setwebproxy", "Wi-Fi", "127.0.0.1", "9090"]))
        #expect(calls.value.contains(["-setsecurewebproxy", "Thunderbolt Bridge", "127.0.0.1", "9090"]))
        #expect(!calls.value.contains { $0.contains("USB LAN") })
        try proxy.disable()
        #expect(calls.value.contains(["-setwebproxystate", "Wi-Fi", "off"]))
    }

    @Test
    func aPendingRestoreIsReportedWhileTheBackupExists() throws {
        let proxy = SystemProxy(run: NetworkSetupSpy().run, backupURL: backup, files: files.access)
        #expect(!proxy.hasPendingRestore)
        try proxy.enable(port: 9090)
        #expect(proxy.hasPendingRestore)
        #expect(files.folders.contains("/fake-home/.watcher"))
        try proxy.disable()
        #expect(!proxy.hasPendingRestore)
    }

    @Test
    func aFailingProxyWriteIsReportedAndTheBackupKeptForALaterRestore() throws {
        let proxy = SystemProxy(run: { arguments in
            if arguments.first == "-setwebproxy" {
                throw CommandFailure(description: "networksetup -setwebproxy: denied")
            }
            return NetworkSetupSpy().run(arguments)
        }, backupURL: backup, files: files.access)
        #expect(throws: CommandFailure(description: "networksetup -setwebproxy: denied")) {
            try proxy.enable(port: 9090)
        }
        #expect(proxy.hasPendingRestore)
    }

    @Test
    func anUnwritableBackupStopsEnableBeforeAnyProxyChanges() {
        files.fail(.writeAtomically)
        let spy = NetworkSetupSpy()
        let proxy = SystemProxy(run: spy.run, backupURL: backup, files: files.access)
        #expect(throws: FileAccessFake.Failure(operation: .writeAtomically)) { try proxy.enable(port: 9090) }
        #expect(!spy.arguments.contains { $0.first == "-setwebproxy" })
    }

    @Test
    func anUnreadableBackupRestoresByTurningTheProxiesOff() throws {
        files.write(Data("not json".utf8), to: backup.path)
        let spy = NetworkSetupSpy()
        try SystemProxy(run: spy.run, backupURL: backup, files: files.access).disable()
        #expect(spy.arguments.contains(["-setwebproxystate", "Wi-Fi", "off"]))
        #expect(spy.arguments.contains(["-setsecurewebproxystate", "Wi-Fi", "off"]))
        #expect(files.contents(of: backup.path) == nil)
    }

    @Test
    func parseHandlesMissingFields() {
        #expect(
            SystemProxy.parse("Enabled: Yes\nServer: h\nPort: 8080\n") == .init(enabled: true, server: "h", port: 8080)
        )
        #expect(SystemProxy.parse("") == .init(enabled: false, server: "", port: 0))
    }

    @Test
    func networksetupRunsTheSystemToolWithItsErrorOutputMerged() throws {
        let spy = CommandRunnerSpy(result: CommandResult(status: 0, output: Data("Wi-Fi\n".utf8)))
        #expect(try SystemProxy.networksetup(using: spy.runner)(["-listallnetworkservices"]) == "Wi-Fi\n")
        #expect(spy.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/sbin/networksetup"),
            arguments: ["-listallnetworkservices"],
            mergesErrorOutput: true
        )])
    }

    @Test
    func networksetupFailingThrowsWhatItPrinted() {
        let spy = CommandRunnerSpy(result: CommandResult(status: 14, output: Data("no such service".utf8)))
        #expect(throws: CommandFailure(description: "networksetup -getwebproxy X: no such service")) {
            try SystemProxy.networksetup(using: spy.runner)(["-getwebproxy", "X"])
        }
    }
}
