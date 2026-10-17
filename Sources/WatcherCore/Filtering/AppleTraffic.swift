import Foundation

/// Apple's own background traffic, which most debugging sessions would rather not see.
public enum AppleTraffic {
    private static let hosts = HostList([
        "*.apple.com",
        "apple.com",
        "*.icloud.com",
        "icloud.com",
        "*.mzstatic.com",
        "*.cdn-apple.com",
        "*.apple-dns.net",
        "*.aaplimg.com",
        "*.apple.news",
        "*.itunes.com",
        "*.icloud-content.com",
    ])

    public static func isApple(_ host: String) -> Bool {
        hosts.matches(host)
    }
}
