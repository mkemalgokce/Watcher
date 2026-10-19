import AppKit
import WatcherCore

/// Icons for the apps that send requests and the websites they talk to, loaded once and cached.
@MainActor @Observable
final class IconStore {
    // Filled while views are drawn, so they must not count as observable changes: writing observed state during a view
    // update re-renders every icon. Only favicons, which arrive later, are observed.
    @ObservationIgnored private var appIcons: [String: NSImage] = [:]
    @ObservationIgnored private var missingApps: Set<String> = []
    /// One observed slot per site, so an icon that arrives redraws only its own row, not every row of a long sidebar.
    @ObservationIgnored private var favicons: [String: FaviconSlot] = [:]
    @ObservationIgnored private(set) var requested: Set<String> = []

    @ObservationIgnored private let preferences: any Preferences
    @ObservationIgnored private let files: FileAccess
    @ObservationIgnored private let workspace: any WorkspaceOpener
    @ObservationIgnored private let cacheFolder: URL
    @ObservationIgnored private let homeDirectory: URL
    @ObservationIgnored private let download: FaviconDownload

    init(
        preferences: any Preferences,
        files: FileAccess,
        workspace: any WorkspaceOpener,
        paths: SupportPaths,
        homeDirectory: URL,
        download: @escaping FaviconDownload
    ) {
        self.preferences = preferences; self.files = files; self.workspace = workspace
        cacheFolder = paths.faviconsDirectory; self.homeDirectory = homeDirectory; self.download = download
    }

    convenience init(_ dependencies: AppDependencies) {
        self.init(
            preferences: dependencies.preferences, files: dependencies.files, workspace: dependencies.workspace,
            paths: dependencies.paths, homeDirectory: dependencies.homeDirectory, download: dependencies.faviconDownload
        )
    }

    // MARK: Apps

    /// Apps show their own icon (from the bundle when it is known, else found by name); everything else a symbol.
    /// A record from before kinds existed has none, and counts as an app.
    func icon(forApp name: String, kind: ClientKind?, bundlePath: String?) -> ClientIcon {
        switch kind ?? .app {
        case .tool: return .symbol("terminal")
        case .service: return .symbol("gearshape")
        case .device: return .symbol("iphone")
        case .app:
            let image = bundlePath.map(bundleIcon(at:)) ?? appIcon(for: name)
            return image.map(ClientIcon.image) ?? .symbol("app")
        }
    }

    private func bundleIcon(at path: String) -> NSImage? {
        if let icon = appIcons[path] {
            return icon
        }
        if missingApps.contains(path) {
            return nil
        }
        // macOS draws an iOS app bundle (a Simulator app) as a no-entry sign, so read the icon file it names instead.
        let isIOSBundle = path.contains("/CoreSimulator/") || files.fileExists("\(path)/Info.plist")
        guard let icon = isIOSBundle ? iOSBundleIcon(at: path) : workspace.icon(forFile: path) else {
            missingApps.insert(path)
            return nil
        }
        appIcons[path] = icon
        return icon
    }

    /// The first icon file listed under `CFBundleIcons` (iPhone, then iPad), largest scale first.
    private func iOSBundleIcon(at path: String) -> NSImage? {
        let bundle = URL(fileURLWithPath: path)
        guard let data = try? files.read(bundle.appendingPathComponent("Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let names = ["CFBundleIcons", "CFBundleIcons~ipad"].flatMap { key -> [String] in
            let primary = (info[key] as? [String: Any])?["CFBundlePrimaryIcon"] as? [String: Any]
            return primary?["CFBundleIconFiles"] as? [String] ?? []
        }
        let suffixes = ["@3x.png", "@2x.png", ".png", "@2x~ipad.png", "~ipad.png"]
        let candidates = names.flatMap { name in suffixes.map { name + $0 } }
        return candidates.lazy
            .compactMap { try? self.files.read(bundle.appendingPathComponent($0)) }
            .compactMap(NSImage.init(data:))
            .first
    }

    func appIcon(for process: String) -> NSImage? {
        if let icon = appIcons[process] {
            return icon
        }
        if missingApps.contains(process) {
            return nil
        }
        guard let url = appBundle(for: process) else { missingApps.insert(process); return nil }
        let icon = workspace.icon(forFile: url.path)
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
        if ["com.apple.WebKit.Networking", "com.apple.WebKit"].contains(name) {
            name = "Safari"
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// The name shown for a client: the owner's as recorded, but a legacy record (no raw process saved)
    /// only has a process name, whose helper suffix is folded into its app.
    nonisolated static func displayName(_ name: String, isLegacy: Bool) -> String {
        isLegacy ? appName(forProcess: name) : name
    }

    private func appBundle(for process: String) -> URL? {
        // Safari & WebKit is what every WebView app's traffic is filed under; it only borrows Safari's icon.
        let name = process == "Safari & WebKit" ? "Safari" : Self.appName(forProcess: process)
        let folders = Self.systemApplicationFolders + [homeDirectory.appendingPathComponent("Applications").path]
        return folders
            .map { URL(fileURLWithPath: $0).appendingPathComponent("\(name).app") }
            .first { files.fileExists($0.path) }
    }

    private static let systemApplicationFolders = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
    ]

    // MARK: Websites

    func favicon(for domain: String, fetch: Bool = true) -> NSImage? {
        let slot = slot(for: domain)
        let hasNoSite = ToolValidation.isIPAddress(domain) || !domain.contains(".")
        if slot.image == nil, fetch, preferences.websiteIconsEnabled, !hasNoSite, !requested.contains(domain) {
            requested.insert(domain)
            Task { [files, cacheFolder, download] in
                let icon = await Self.loadFavicon(domain, files: files, cacheFolder: cacheFolder, download: download)
                if let icon {
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

    /// Off the main actor: reading the cache and decoding images for hundreds of sites would freeze the window.
    private nonisolated static func loadFavicon(
        _ domain: String, files: FileAccess, cacheFolder: URL, download: FaviconDownload
    ) async -> NSImage? {
        let cached = cacheFolder.appendingPathComponent("\(domain).ico")
        if let data = try? files.read(cached), let image = NSImage(data: data) {
            return image
        }
        for host in [domain, "www.\(domain)"] {
            guard let url = URL(string: "https://\(host)/favicon.ico"), let data = await download(url),
                  data.count < maxFaviconBytes, let image = NSImage(data: data) else { continue }
            try? files.createDirectory(cacheFolder)
            try? files.writeAtomically(data, cached)
            return image
        }
        return nil
    }

    private nonisolated static let maxFaviconBytes = 512 * 1024
}

/// What stands for a client in a list: its own icon, or a symbol.
enum ClientIcon: Equatable {
    case image(NSImage), symbol(String)
}

/// One site's icon; observed on its own so its arrival redraws a single row.
@MainActor @Observable
final class FaviconSlot {
    var image: NSImage?
}
