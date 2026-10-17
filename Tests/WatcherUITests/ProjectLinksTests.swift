@testable import WatcherUI
import XCTest

/// The About window and Help menu point at the real project, author and sponsor pages.
final class ProjectLinksTests: XCTestCase {
    func testLinksPointAtTheProjectOnGitHub() {
        XCTAssertEqual(ProjectLinks.repository.absoluteString, "https://github.com/mkemalgokce/watcher")
        XCTAssertEqual(ProjectLinks.issues.absoluteString, "https://github.com/mkemalgokce/watcher/issues/new/choose")
        XCTAssertEqual(ProjectLinks.sponsor.absoluteString, "https://github.com/sponsors/mkemalgokce")
        XCTAssertEqual(ProjectLinks.author.absoluteString, "https://github.com/mkemalgokce")
        XCTAssertEqual(ProjectLinks.authorName, "Mustafa Kemal Gökçe")
    }
}
