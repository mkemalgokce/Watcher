import Foundation
import WatcherCore

/// The file extension that suits captured content.
enum ExternalOpen {
    static func fileExtension(contentType: String?, data: Data) -> String {
        FileExtension.preferred(forContentType: contentType)
            ?? FileExtension.preferred(forContentType: Base64Finder.imageMime(data))
            ?? (String(data: data.prefix(4096), encoding: .utf8) != nil ? "txt" : "bin")
    }
}
