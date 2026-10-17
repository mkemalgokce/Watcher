import Testing
@testable import WatcherUI

/// The About window and Help menu point at the real project, author and sponsor pages.
struct ProjectLinksTests {
    @Test
    func linksPointAtTheProjectOnGitHub() {
        #expect(ProjectLinks.repository.absoluteString == "https://github.com/mkemalgokce/watcher")
        #expect(ProjectLinks.issues.absoluteString == "https://github.com/mkemalgokce/watcher/issues/new/choose")
        #expect(ProjectLinks.sponsor.absoluteString == "https://github.com/sponsors/mkemalgokce")
        #expect(ProjectLinks.author.absoluteString == "https://github.com/mkemalgokce")
        #expect(ProjectLinks.authorName == "Mustafa Kemal Gökçe")
    }
}
