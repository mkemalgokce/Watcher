import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// What a new user meets: the welcome sheet, device setup, the About window and a startup problem.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct OnboardingScreenTests {
    private static let withDevices = DevicesViewModel.DeviceProbe(
        simulators: { [.init(udid: "A1", name: "iPhone 16", runtime: "iOS 18.0", isBooted: true)] },
        androidDevices: { [AndroidDevice(serial: "emulator-5554", model: "Pixel 8", isEmulator: true)] },
        isMacTrusted: { false },
        lanAddresses: { ["192.168.1.5"] }
    )

    private func model(devices: DevicesViewModel.DeviceProbe = Self.withDevices) throws -> AppModel {
        try AppModel(dependencies: .test(devices: devices))
    }

    @Test
    func theWelcomeSheet() async throws {
        try await ImageSnapshot.verify(
            WelcomeView().environment(model()), size: CGSize(width: 560, height: 640), named: "welcome"
        )
    }

    @Test(arguments: DeviceSetupView.Target.allCases)
    func deviceSetup(target: DeviceSetupView.Target) async throws {
        let model = try model()
        await model.devices.refresh()
        await ImageSnapshot.verify(
            DeviceSetupView(target: target).environment(model), size: CGSize(width: 780, height: 580),
            named: target.rawValue, until: { !model.devices.isScanning }
        )
    }

    @Test
    func deviceSetupFindingNothing() async throws {
        let model = try model(devices: .none)
        await model.devices.refresh()
        await ImageSnapshot.verify(
            DeviceSetupView(target: .simulator).environment(model), size: CGSize(width: 780, height: 580),
            named: "none", until: { !model.devices.isScanning }
        )
    }

    @Test
    func theAboutWindow() async throws {
        try await ImageSnapshot.verify(
            AboutView().environment(model()), size: CGSize(width: 520, height: 700), named: "about"
        )
    }

    @Test
    func theStartupProblemBanner() async throws {
        var dependencies = try AppDependencies.test()
        dependencies.startupProblem = StartupProblem(
            message: "Watcher could not open ~/.watcher. This session is recorded into a temporary folder.",
            folder: URL(fileURLWithPath: "/fake-home/.watcher")
        )
        let model = AppModel(dependencies: dependencies)
        await ImageSnapshot.verify(
            StartupProblemBanner().environment(model), size: CGSize(width: 900, height: 44), named: "banner"
        )
    }
}
