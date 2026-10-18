public struct NetworkProfile: Codable, Equatable, Sendable {
    public var name: String
    /// 0 means unlimited.
    public var downloadKbps: Int
    public var uploadKbps: Int
    public var latencyMilliseconds: Int
    public var packetLossPercent: Int

    public init(name: String, downloadKbps: Int = 0, uploadKbps: Int = 0, latencyMilliseconds: Int = 0, packetLossPercent: Int = 0) {
        self.name = name; self.downloadKbps = downloadKbps; self.uploadKbps = uploadKbps
        self.latencyMilliseconds = latencyMilliseconds; self.packetLossPercent = packetLossPercent
    }

    public static let presets: [NetworkProfile] = [
        .init(name: "3G", downloadKbps: 780, uploadKbps: 330, latencyMilliseconds: 100),
        .init(name: "Edge", downloadKbps: 240, uploadKbps: 200, latencyMilliseconds: 400),
        .init(name: "LTE", downloadKbps: 12000, uploadKbps: 5000, latencyMilliseconds: 50),
        .init(name: "Wi-Fi", downloadKbps: 40000, uploadKbps: 33000, latencyMilliseconds: 1),
        .init(name: "very_bad_network", downloadKbps: 100, uploadKbps: 50, latencyMilliseconds: 800, packetLossPercent: 10),
        .init(name: "100_percent_loss", packetLossPercent: 100),
    ]
}
