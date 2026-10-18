import ArgumentParser
import Foundation
import Testing
@testable import watcher_cli
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct AndroidCommandTests {
    static let emulator = "emulator-5554          device product:sdk model:sdk_gphone64 device:emu"
    static let phone = "R58M123                device usb:1-1 model:Pixel_7 transport_id:2"

    @Test
    func defaultsListDevicesForTheStoredPort() throws {
        let android = try AndroidCommand.parse([])
        #expect(android.action == .list)
        #expect(android.serial == nil)
        #expect(android.port == nil)
    }

    @Test(arguments: [
        ("list", AndroidCommand.Action.list), ("cert", .cert), ("proxy", .proxy), ("unproxy", .unproxy),
    ])
    func readsTheAction(word: String, action: AndroidCommand.Action) throws {
        let android = try AndroidCommand.parse([word, "--serial", "emulator-5554", "--port", "8888"])
        #expect(android.action == action)
        #expect(android.serial == "emulator-5554")
        #expect(android.port == 8888)
    }

    @Test(arguments: ["0", "65536", "-1"])
    func rejectsAPortTheDeviceCannotPointAt(port: String) {
        #expect(throws: (any Error).self) { try AndroidCommand.parse(["proxy", "--port=\(port)"]) }
    }

    @Test(arguments: [["flash"], ["--port", "x"]])
    func rejectsAnUnknownActionOrMalformedPort(arguments: [String]) {
        #expect(throws: (any Error).self) { try AndroidCommand.parse(arguments) }
    }

    @Test
    func listingNoDevicesSaysHowToConnectOne() throws {
        let cli = Self.harness(devices: [])
        try AndroidCommand.parse([]).run(in: cli.environment)
        #expect(cli.printed == ["No Android device. Start an emulator or connect a phone with USB debugging."])
        #expect(cli.commands.calls == ["adb devices -l"])
    }

    @Test
    func listingPrintsSerialKindAndModelTabSeparated() throws {
        let cli = Self.harness(devices: [Self.emulator, Self.phone])
        try AndroidCommand.parse(["list"]).run(in: cli.environment)
        #expect(cli.printed == ["emulator-5554\temulator\tsdk_gphone64", "R58M123\tdevice\tPixel_7"])
    }

    @Test
    func withoutAdbItSaysHowToInstallIt() throws {
        let cli = CLIHarness()
        let command = try AndroidCommand.parse([])
        #expect(throws: CommandFailure(
            description: "adb not found. Install Android platform-tools (brew install android-platform-tools)."
        )) { try command.run(in: cli.environment) }
        #expect(cli.commands.commands.isEmpty)
    }

    @Test(arguments: ["cert", "proxy", "unproxy"])
    func anActionWithoutAnyDeviceFails(action: String) throws {
        let cli = Self.harness(devices: [])
        let error = try Self.validationError(running: [action], in: cli)
        #expect(error?.message == "No Android device is connected.")
        #expect(cli.commands.calls == ["adb devices -l"])
    }

    @Test
    func anActionWithSeveralDevicesNeedsASerial() throws {
        let cli = Self.harness(devices: [Self.emulator, Self.phone])
        let error = try Self.validationError(running: ["cert"], in: cli)
        #expect(error?.message == "Several devices are connected; pass --serial.")
    }

    @Test(arguments: [1, 2])
    func aSerialNoConnectedDeviceHasIsNamedInTheError(connected: Int) throws {
        let cli = Self.harness(devices: Array([Self.phone, Self.emulator].prefix(connected)))
        let error = try Self.validationError(running: ["cert", "--serial", "missing"], in: cli)
        #expect(error?.message == "No device with serial missing is connected.")
        #expect(cli.commands.calls == ["adb devices -l"])
    }

    @Test
    func certCopiesTheRootCertificateToTheOnlyDevice() throws {
        let cli = Self.harness(devices: [Self.phone])
        try AndroidCommand.parse(["cert"]).run(in: cli.environment)
        #expect(cli.commands.calls == [
            "adb devices -l",
            "adb -s R58M123 push \(cli.supportFile("watcher-ca.pem")) /sdcard/Download/watcher-ca.cer",
        ])
        #expect(cli.files.paths.contains(cli.supportFile("watcher-ca.pem")))
        #expect(cli.printed == [
            "Copied to Download/watcher-ca.cer. "
                + "On the device: Settings → Security → Install a certificate → CA certificate.",
        ])
    }

    @Test
    func theSerialPicksOneOfSeveralDevices() throws {
        let cli = Self.harness(devices: [Self.emulator, Self.phone])
        try AndroidCommand.parse(["unproxy", "--serial", "R58M123"]).run(in: cli.environment)
        #expect(cli.commands.calls.last == "adb -s R58M123 shell settings put global http_proxy :0")
        #expect(cli.printed == ["Proxy cleared"])
    }

    @Test(arguments: [
        (emulator, "emulator-5554", "10.0.2.2:8888"), (phone, "R58M123", "192.168.1.20:8888"),
    ])
    func proxyPointsTheDeviceAtThisMac(device: String, serial: String, endpoint: String) throws {
        let cli = Self.harness(devices: [device], lanAddresses: [.init(interface: "en0", ip: "192.168.1.20")])
        try AndroidCommand.parse(["proxy", "--port", "8888"]).run(in: cli.environment)
        #expect(cli.commands.calls.last == "adb -s \(serial) shell settings put global http_proxy \(endpoint)")
        #expect(cli.printed == ["Proxy set to \(endpoint)"])
    }

    @Test
    func proxyWithoutAPortPointsTheDeviceAtTheStoredOne() throws {
        let cli = Self.harness(devices: [Self.emulator])
        try cli.environment.settings.update { $0.port = 7777 }
        try AndroidCommand.parse(["proxy"]).run(in: cli.environment)
        #expect(cli.commands.calls.last == "adb -s emulator-5554 shell settings put global http_proxy 10.0.2.2:7777")
    }

    @Test
    func proxyingAPhoneNeedsALANAddress() throws {
        let cli = Self.harness(devices: [Self.phone])
        let error = try Self.validationError(running: ["proxy"], in: cli)
        #expect(error?.message == "No network address found for this Mac.")
        #expect(cli.commands.calls == ["adb devices -l"])
    }

    @Test
    func aFailingAdbCallIsReported() throws {
        let commands = CommandRunnerSpy(respond: { command in
            let failed = command.arguments.contains("push")
            let output = failed ? "no space" : Self.listing([Self.phone])
            return CommandResult(status: failed ? 1 : 0, output: Data(output.utf8))
        })
        let cli = CLIHarness(files: Self.filesWithAdb(), commands: commands)
        let command = try AndroidCommand.parse(["cert"])
        #expect(throws: CommandFailure.self) { try command.run(in: cli.environment) }
        #expect(cli.printed.isEmpty)
    }

    private static func listing(_ devices: [String]) -> String {
        (["List of devices attached"] + devices).joined(separator: "\n") + "\n"
    }

    private static func filesWithAdb() -> FileAccessFake {
        FileAccessFake(executables: ["/opt/homebrew/bin/adb"])
    }

    private static func harness(devices: [String], lanAddresses: [LocalNetwork.Address] = []) -> CLIHarness {
        let listing = listing(devices)
        let commands = CommandRunnerSpy(respond: { command in
            CommandResult(status: 0, output: Data((command.arguments.first == "devices" ? listing : "").utf8))
        })
        return CLIHarness(files: filesWithAdb(), commands: commands, lanAddresses: lanAddresses)
    }

    private static func validationError(running arguments: [String], in cli: CLIHarness) throws -> ValidationError? {
        let command = try AndroidCommand.parse(arguments)
        return #expect(throws: ValidationError.self) { try command.run(in: cli.environment) }
    }

    @Test
    func certNeverPushesWhenTheRootCertificateCannotBeCreated() throws {
        let cli = Self.harness(devices: [Self.phone])
        cli.files.fail(.createDirectory)
        let command = try AndroidCommand.parse(["cert"])
        #expect(throws: FileAccessFake.Failure(operation: .createDirectory)) { try command.run(in: cli.environment) }
        #expect(!cli.commands.calls.contains { $0.contains(" push ") })
        #expect(cli.printed.isEmpty)
    }
}
