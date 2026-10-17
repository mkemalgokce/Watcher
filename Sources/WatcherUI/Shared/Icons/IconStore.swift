import AppKit
import SwiftUI
import WatcherCore

/// Icons for the apps that send requests and the websites they talk to, loaded once and cached.
@MainActor @Observable
final class IconStore {
    static let shared = IconStore()

    // Filled while views are drawn, so they must not count as observable changes: writing observed state during a view
    // update re-renders every icon. Only favicons, which arrive later, are observed.
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    @ObservationIgnored private var missingApps: Set<String> = []
    /// One observed slot per site, so an icon that arrives redraws only its own row, not every row of a long sidebar.
    @ObservationIgnored private var favicons: [String: FaviconSlot] = [:]
    @ObservationIgnored private var requested: Set<String> = []

    /// Website icons are fetched from the sites themselves; people who do not want that can switch it off in Settings.
    static var websiteIconsEnabled: Bool {
        UserDefaults.standard.object(forKey: "icons.websites") as? Bool ?? true
    }

    // MARK: Apps

    func appIcon(for process: String) -> NSImage? {
        if let icon = appIcons[process] {
            return icon
        }
        if missingApps.contains(process) {
            return nil
        }
        guard let url = Self.appBundle(for: process) else { missingApps.insert(process); return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        appIcons[process] = icon
        return icon
    }

    /// `Google Chrome Helper (Renderer)` → `Google Chrome.app`. Command-line tools (curl, python3) have no bundle.
    nonisolated static func appName(forProcess process: String) -> String {
        var name = process
        if let range = name.range(of: " Helper") {
            name = String(name[..<range.lowerBound])
        }
        if let range = name.range(of: " Web Content") {
            name = String(name[..<range.lowerBound])
        }
        if name == "com.apple.WebKit.Networking" || name == "com.apple.WebKit" {
            name = "Safari"
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    private static func appBundle(for process: String) -> URL? {
        let name = appName(forProcess: process)
        let folders = [
            "/Applications",
            "/Applications/Utilities",
            "/System/Applications",
            "/System/Applications/Utilities",
            "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
            "\(NSHomeDirectory())/Applications",
        ]
        for folder in folders {
            let url = URL(fileURLWithPath: folder).appendingPathComponent("\(name).app")
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    // MARK: Websites

    func favicon(for domain: String, fetch: Bool = true) -> NSImage? {
        let slot = slot(for: domain)
        let isAddress = domain.allSatisfy { $0.isNumber || $0 == "." }
        if slot.image == nil, fetch, Self.websiteIconsEnabled, !isAddress, !requested.contains(domain) {
            requested.insert(domain)
            Task {
                if let icon = await Self.loadFavicon(domain) {
                    setFavicon(icon, for: domain)
                }
            }
        }
        return slot.image
    }

    func setFavicon(_ icon: NSImage, for domain: String) {
        slot(for: domain).image = icon
    }

    private func slot(for domain: String) -> FaviconSlot {
        if let slot = favicons[domain] {
            return slot
        }
        let slot = FaviconSlot()
        favicons[domain] = slot
        return slot
    }

    private nonisolated static var cacheFolder: URL {
        WatcherPaths.supportDirectory.appendingPathComponent("favicons", isDirectory: true)
    }

    /// Off the main actor: reading the cache and decoding images for hundreds of sites would freeze the window.
    private nonisolated static func loadFavicon(_ domain: String) async -> NSImage? {
        let cached = cacheFolder.appendingPathComponent("\(domain).ico")
        if let data = try? Data(contentsOf: cached), let image = NSImage(data: data) {
            return image
        }
        // Straight to the site: an empty proxy dictionary keeps this out of the system proxy, i.e. out of Watcher's own list.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        for host in [domain, "www.\(domain)"] {
            guard let url = URL(string: "https://\(host)/favicon.ico"),
                  let (data, response) = try? await session.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count < 512 * 1024, let image = NSImage(data: data) else { continue }
            try? FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
            try? data.write(to: cached)
            return image
        }
        return nil
    }
}

/// One site's icon; observed on its own so its arrival redraws a single row.
@MainActor @Observable
final class FaviconSlot {
    var image: NSImage?
}
