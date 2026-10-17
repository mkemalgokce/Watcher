import Foundation

/// Where the project lives, for the About window and the Help menu.
enum ProjectLinks {
    static let authorName = "Mustafa Kemal Gökçe"
    static let author = URL(string: "https://github.com/mkemalgokce")!
    static let repository = URL(string: "https://github.com/mkemalgokce/watcher")!
    static let issues = URL(string: "https://github.com/mkemalgokce/watcher/issues/new/choose")!
    static let sponsor = URL(string: "https://github.com/sponsors/mkemalgokce")!
    /// The licences of the bundled packages; present only in a packaged app.
    static var thirdPartyNotices: URL? {
        Bundle.main.url(forResource: "THIRD_PARTY_NOTICES", withExtension: "md")
    }
}
