import Foundation

/// What this build is and where it runs, read once from the system so About can be tested with any answer.
struct AppInfo: Sendable {
    var bundleIdentifier: String?
    var shortVersion: String?
    var buildNumber: String?
    var operatingSystem: OperatingSystemVersion
    var architecture: String
    var homeDirectory: String

    static let live: AppInfo = {
        let info = Bundle.main.infoDictionary ?? [:]
        #if arch(arm64)
            let architecture = "arm64"
        #else
            let architecture = "x86_64"
        #endif
        return AppInfo(
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            shortVersion: info["CFBundleShortVersionString"] as? String,
            buildNumber: info["CFBundleVersion"] as? String,
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersion,
            architecture: architecture,
            homeDirectory: NSHomeDirectory()
        )
    }()

    /// "Version 1.0 (1)" in a packaged app; `swift run`, Xcode and tests run inside another bundle, whose version is
    /// not Watcher's.
    var versionText: String {
        guard bundleIdentifier == "dev.watcher.app", let shortVersion else { return "Development build" }
        return "Version \(shortVersion) (\(buildNumber ?? "?"))"
    }

    var diagnostics: String {
        let system = operatingSystem
        let version = "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)"
        return "Watcher \(versionText) · macOS \(version) · \(architecture)"
    }

    /// The path with the home folder written as `~`, so a screenshot or bug report does not carry the user name.
    func abbreviatingHome(_ path: String) -> String {
        guard path == homeDirectory || path.hasPrefix(homeDirectory + "/") else { return path }
        return "~" + path.dropFirst(homeDirectory.count)
    }
}
