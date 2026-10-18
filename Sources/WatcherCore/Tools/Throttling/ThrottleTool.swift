import Foundation

/// Simulates a slow or lossy network: latency, bandwidth and dropped requests.
struct ThrottleTool: Tool {
    let name = "Network Throttling"
    var inspectsResponses: Bool {
        true
    }

    private let profile: NetworkProfile
    private let host: String

    /// A number from 1 to 100; the request is dropped when it is at most the loss percent.
    private let roll: @Sendable () -> Int
    private let sleep: Sleep

    init(
        settings: ThrottleSettings,
        roll: @escaping @Sendable () -> Int = { Int.random(in: 1 ... 100) },
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        profile = settings.profile; host = settings.host.lowercased()
        self.roll = roll; self.sleep = sleep
    }

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        guard applies(to: request) else { return .forward }
        if roll() <= profile.packetLossPercent {
            return .respond(ProxyServer.message(504, "Watcher simulated packet loss (\(profile.name))"))
        }
        await pause(bytes: request.body.count, kbps: profile.uploadKbps)
        return .forward
    }

    func intercept(response: inout ResponseRecord, for request: RequestRecord) async {
        guard applies(to: request) else { return }
        await pause(bytes: response.body.count, kbps: profile.downloadKbps)
    }

    private func applies(to request: RequestRecord) -> Bool {
        host.isEmpty || host == request.host.lowercased() || host == "\(request.host):\(request.port)".lowercased()
    }

    private func pause(bytes: Int, kbps: Int) async {
        let transfer = kbps > 0 ? Double(bytes) * 8 / (Double(kbps) * 1000) : 0
        let seconds = Double(profile.latencyMilliseconds) / 1000 + transfer
        if seconds > 0 {
            try? await sleep(.seconds(seconds))
        }
    }
}
