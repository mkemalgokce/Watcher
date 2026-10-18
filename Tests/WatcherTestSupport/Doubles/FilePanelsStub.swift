import Foundation
import UniformTypeIdentifiers
import WatcherUI

/// Answers every open and save panel with the URL it was given (nil acts as Cancel) and records what was asked.
public final class FilePanelsStub: FilePanels, @unchecked Sendable {
    public struct SaveRequest: Equatable, Sendable {
        public let suggestedName: String
        public let contentTypes: [UTType]

        public init(suggestedName: String, contentTypes: [UTType]) {
            self.suggestedName = suggestedName; self.contentTypes = contentTypes
        }
    }

    private let lock = NSLock()
    private let openURL: URL?
    private let saveURL: URL?
    private var opens: [Bool] = []
    private var saves: [SaveRequest] = []

    public init(open: URL? = nil, save: URL? = nil) {
        openURL = open; saveURL = save
    }

    /// One entry per open panel: whether it asked for a folder.
    public var openRequests: [Bool] {
        lock.withLock { opens }
    }

    public var saveRequests: [SaveRequest] {
        lock.withLock { saves }
    }

    public func chooseItem(directory: Bool) -> URL? {
        lock.withLock { opens.append(directory) }
        return openURL
    }

    public func chooseSaveLocation(suggestedName: String, contentTypes: [UTType]) -> URL? {
        lock.withLock { saves.append(SaveRequest(suggestedName: suggestedName, contentTypes: contentTypes)) }
        return saveURL
    }
}
