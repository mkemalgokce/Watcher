import Testing
@testable import WatcherUI

/// Updates are switched on only in a build that names where to look and how to trust what it finds; any other build,
/// such as `swift run` or a test, has nothing to update from.
@Suite(.tags(.unit))
struct UpdateConfigurationTests {
    private let feed = "https://github.com/mkemalgokce/Watcher/releases/latest/download/appcast.xml"
    private let key = "q6Xw3oYyZ0o7r3c0jv5m9w1h2mEw9VqD2Yc0n1l8k4E="

    @Test
    func aFeedAndAPublicKeyTurnUpdatesOn() {
        #expect(UpdateConfiguration.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": key]))
    }

    @Test
    func aBuildWithoutAnInfoDictionaryHasNoUpdates() {
        #expect(!UpdateConfiguration.isConfigured(nil))
        #expect(!UpdateConfiguration.isConfigured([:]))
    }

    @Test(arguments: [
        ["SUPublicEDKey": "key"],
        ["SUFeedURL": "https://example.com/appcast.xml"],
        ["SUFeedURL": "", "SUPublicEDKey": "key"],
        ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": ""],
        ["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": "  "],
    ])
    func eitherPartMissingOrEmptyMeansNoUpdates(info: [String: String]) {
        #expect(!UpdateConfiguration.isConfigured(info))
    }

    @Test(arguments: [
        "http://example.com/appcast.xml",
        "ftp://example.com/appcast.xml",
        "example.com/appcast.xml",
        "not a url",
    ])
    func aFeedThatIsNotHTTPSMeansNoUpdates(feed: String) {
        #expect(!UpdateConfiguration.isConfigured(["SUFeedURL": feed, "SUPublicEDKey": key]))
    }

    @Test
    func valuesThatAreNotTextMeanNoUpdates() {
        #expect(!UpdateConfiguration.isConfigured(["SUFeedURL": 3, "SUPublicEDKey": key]))
    }
}
