import AppKit
import SwiftUI
import WatcherCore

/// Watcher's own icon, so the Dock shows it even when the app runs unbundled from Xcode or `swift run`.
public enum WatcherAppIcon {
    @MainActor public static var image: NSImage? {
        Bundle.module.url(forResource: "AppIcon", withExtension: "icns").flatMap(NSImage.init(contentsOf:))
    }

    /// The menu bar glyph: a dot in the lens while the proxy listens. A template image, so macOS colours it for light, dark and tinted bars.
    @MainActor public static func menuBar(running: Bool) -> NSImage {
        // Inline rather than a resource: the packaged app does not carry SwiftPM's resource bundle, and Bundle.module would trap there.
        let dot = running ? ##"<circle cx="22" cy="18" r="2.3" fill="#000"/>"## : ""
        let svg = ##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 44 36" fill="none" stroke="#000" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><circle cx="22" cy="18" r="7.5"/><path d="M4 14 H11.5 M32.5 14 H40 M36.5 10.5 L40 14 L36.5 17.5"/><path d="M40 22 H32.5 M11.5 22 H4 M7.5 18.5 L4 22 L7.5 25.5"/>"## + dot + "</svg>"
        let image = NSImage(data: Data(svg.utf8)) ?? NSImage()
        image.size = NSSize(width: 22, height: 18)
        image.isTemplate = true
        return image
    }
}

/// The app's own icon inside its windows; follows the Dock icon, including its light, dark and tinted looks.
struct WatcherLogo: View {
    var size: CGFloat = 56

    var body: some View {
        // The packaged app's icon is the system's (Liquid Glass on macOS 26); unbundled runs (swift run, Xcode, tests) would show
        // their host's, so they read Watcher's own icns instead.
        let image = Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") != nil ? NSApp.applicationIconImage : WatcherAppIcon.image ?? NSApp.applicationIconImage
        Image(nsImage: image ?? NSImage()).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
    }
}

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

/// The app's icon, or a terminal symbol for command-line tools.
struct AppIconView: View {
    let process: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = IconStore.shared.appIcon(for: process) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size).accessibilityHidden(true)
        } else {
            Image(systemName: "terminal").font(.system(size: size * 0.75)).foregroundStyle(.secondary).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}

/// The website's favicon, or a globe while it loads or when the site has none.
struct SiteIconView: View {
    let domain: String
    var size: CGFloat = 16

    var body: some View {
        if let icon = IconStore.shared.favicon(for: domain) {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: 3)).accessibilityHidden(true)
        } else {
            Image(systemName: "globe").font(.system(size: size * 0.8)).foregroundStyle(.secondary).frame(width: size, height: size).accessibilityHidden(true)
        }
    }
}
