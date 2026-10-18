import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct SimulatorCertificateTests {
    @Test
    func listsAvailableSimulatorsBootedFirst() throws {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-5":[
          {"udid":"B","name":"iPhone 15","state":"Shutdown","isAvailable":true},
          {"udid":"A","name":"iPhone 15 Pro","state":"Booted","isAvailable":true},
          {"udid":"C","name":"Broken","state":"Shutdown","isAvailable":false}],
         "com.apple.CoreSimulator.SimRuntime.watchOS-10-0":[{"udid":"W","name":"Watch","state":"Shutdown"}]}}
        """
        let list = try SimulatorCertificate.simulators { arguments in
            #expect(arguments == ["simctl", "list", "devices", "--json"]); return json
        }
        #expect(list.map(\.udid) == ["A", "B", "W"])
        #expect(list.first == .init(udid: "A", name: "iPhone 15 Pro", runtime: "iOS 17.5", isBooted: true))
    }

    @Test
    func installAddsTheRootToTheNamedDeviceThroughSimctl() throws {
        let calls = LockedBox<[[String]]>([])
        let cert = URL(fileURLWithPath: "/tmp/watcher-ca.pem")
        try SimulatorCertificate.install(certificate: cert, device: "booted") { calls.mutate($0); return "" }
        try SimulatorCertificate.install(certificate: cert, device: "6F2E-AB12") { calls.mutate($0); return "" }
        #expect(calls.value == [
            ["simctl", "keychain", "booted", "add-root-cert", "/tmp/watcher-ca.pem"],
            ["simctl", "keychain", "6F2E-AB12", "add-root-cert", "/tmp/watcher-ca.pem"],
        ])
    }

    @Test(arguments: ["", "booted; rm -rf /", "../x", "a b"])
    func installRejectsOddDeviceNames(_ device: String) {
        let cert = URL(fileURLWithPath: "/tmp/watcher-ca.pem")
        #expect(throws: (any Error).self, "\(device)") {
            try SimulatorCertificate.install(certificate: cert, device: device) { _ in "" }
        }
    }

    @Test
    func xcrunRunsTheDeveloperToolAndThrowsWhatAFailurePrinted() throws {
        let succeeding = CommandRunnerSpy(result: CommandResult(status: 0, output: Data("{}".utf8)))
        #expect(try SimulatorCertificate.xcrun(using: succeeding.runner)(["simctl", "list"]) == "{}")
        #expect(succeeding.commands == [Command(
            executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
            arguments: ["simctl", "list"],
            mergesErrorOutput: true
        )])
        let failing = CommandRunnerSpy(result: CommandResult(status: 1, output: Data("no devices".utf8)))
        #expect(throws: CommandFailure(description: "xcrun simctl list: no devices")) {
            try SimulatorCertificate.xcrun(using: failing.runner)(["simctl", "list"])
        }
    }
}
