import Testing
@testable import WatcherUI

/// The file extension a Content-Type suggests, shared by saving bodies, saving images and opening in other apps.
@Suite(.tags(.unit))
struct FileExtensionTests {
    @Test(arguments: [
        ("application/json", "json"),
        ("application/json; charset=utf-8", "json"),
        (" text/html ;charset=utf-8", "html"),
        ("image/png", "png"),
        ("image/svg+xml", "svg"),
    ])
    func aKnownTypeGivesItsPreferredExtension(contentType: String, expected: String) {
        #expect(FileExtension.preferred(forContentType: contentType) == expected)
    }

    @Test(arguments: [nil, "", "nonsense", "application/x-watcher-unknown"] as [String?])
    func anUnknownOrMissingTypeGivesNone(contentType: String?) {
        #expect(FileExtension.preferred(forContentType: contentType) == nil)
    }
}
