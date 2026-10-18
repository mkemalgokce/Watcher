@testable import WatcherUI

/// Records what would have been read out by VoiceOver.
@MainActor
public final class AnnouncerSpy {
    public private(set) var messages: [String] = []

    public init() {}

    public var announce: Announce {
        { [self] message in messages.append(message) }
    }
}
