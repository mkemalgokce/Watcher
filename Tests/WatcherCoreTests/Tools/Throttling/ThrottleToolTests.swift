import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ThrottleToolTests {
    private let sleeper = SleepSpy()

    private func tool(_ profile: NetworkProfile, host: String = "", roll: Int = 100) -> ThrottleTool {
        ThrottleTool(
            settings: ThrottleSettings(isEnabled: true, profile: profile, host: host),
            roll: { roll },
            sleep: sleeper.sleep
        )
    }

    private func isDropped(_ tool: ThrottleTool, request: RequestRecord = .fixture()) async -> Bool {
        var request = request
        guard case let .respond(response) = await tool.intercept(request: &request) else { return false }
        return response.status == 504
    }

    @Test(arguments: [(0, 1, false), (10, 10, true), (10, 11, false), (100, 100, true)])
    func aRequestIsDroppedWhenTheRollFallsWithinTheLossPercent(loss: Int, roll: Int, dropped: Bool) async {
        let profile = NetworkProfile(name: "lossy", packetLossPercent: loss)
        #expect(await isDropped(tool(profile, roll: roll)) == dropped)
    }

    @Test
    func aDroppedRequestIsNotDelayed() async {
        let profile = NetworkProfile(name: "lossy", latencyMilliseconds: 500, packetLossPercent: 100)
        _ = await isDropped(tool(profile, roll: 1))
        #expect(sleeper.durations.isEmpty)
    }

    @Test
    func anUploadWaitsForTheLatencyPlusItsTransferTime() async {
        // 1000 bytes at 8 kbps take one second.
        let profile = NetworkProfile(name: "slow", uploadKbps: 8, latencyMilliseconds: 100)
        _ = await isDropped(tool(profile), request: .fixture(body: Data(count: 1000)))
        #expect(sleeper.durations == [.seconds(1.1)])
    }

    @Test
    func aDownloadWaitsForTheLatencyPlusItsTransferTime() async {
        let profile = NetworkProfile(name: "slow", downloadKbps: 16, latencyMilliseconds: 0)
        var response = ResponseRecord.fixture(body: Data(count: 1000))
        await tool(profile).intercept(response: &response, for: .fixture())
        #expect(sleeper.durations == [.seconds(0.5)])
    }

    @Test
    func anUnlimitedProfileWithoutLatencyNeverWaits() async {
        let profile = NetworkProfile(name: "fast")
        _ = await isDropped(tool(profile), request: .fixture(body: Data(count: 1000)))
        var response = ResponseRecord.fixture(body: Data(count: 1000))
        await tool(profile).intercept(response: &response, for: .fixture())
        #expect(sleeper.durations.isEmpty)
    }

    @Test(arguments: [
        ("", true), ("API.example.com", true), ("api.example.com:443", true),
        ("api.example.com:8443", false), ("other.example.com", false),
    ])
    func onlyTheChosenHostIsThrottled(host: String, throttled: Bool) async {
        let profile = NetworkProfile(name: "lossy", packetLossPercent: 100)
        let request = RequestRecord.fixture(scheme: "https", host: "api.example.com", port: 443)
        #expect(await isDropped(tool(profile, host: host, roll: 1), request: request) == throttled)
    }
}
