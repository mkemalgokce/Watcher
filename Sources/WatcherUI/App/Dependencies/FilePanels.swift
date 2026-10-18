import Foundation
import UniformTypeIdentifiers

/// The open and save panels; nil means the user cancelled.
public protocol FilePanels: Sendable {
    @MainActor func chooseItem(directory: Bool) -> URL?
    @MainActor func chooseSaveLocation(suggestedName: String, contentTypes: [UTType]) -> URL?
}
