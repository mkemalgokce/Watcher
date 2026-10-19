extension ClientIdentity {
    private static let systemRoots = [
        "/System/Library/", "/Library/Apple/", "/usr/", "/System/Volumes/Preboot/Cryptexes/OS/",
    ]
    private static let daemonRoots = ["/usr/libexec/", "/usr/sbin/", "/sbin/", "/System/", "/Library/Apple/"]
    /// Shared by Safari and every web view, and no public API says which one asked.
    private static let webKitNetworking = "com.apple.WebKit.Networking"

    /// Sorts a process into app, tool or service from where its executable lives.
    static func classify(process: String, executablePath path: String?) -> ClientIdentity {
        func make(_ app: String, _ kind: ClientKind, _ bundle: String? = nil) -> ClientIdentity {
            ClientIdentity(app: app, process: process, kind: kind, bundlePath: bundle)
        }
        if process == webKitNetworking {
            return make("Safari & WebKit", .app)
        }
        guard let path else { return make(process, .service) }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        let last = components.count - 1
        let apps = components.indices.filter { components[$0].hasSuffix(".app") }
        let isSimulator = path.contains("/CoreSimulator/")
        // The executable's own bundle is the innermost .app, with the executable flat inside it or in Contents/MacOS.
        let macOSLayout = apps.last.map {
            $0 == last - 3 && components[$0 + 1] == "Contents" && components[$0 + 2] == "MacOS"
        } ?? false
        guard let own = apps.last, own == last - 1 || macOSLayout else {
            if isSimulator {
                return make("\(process) (Simulator)", .service)
            }
            return make(process, daemonRoots.contains { path.hasPrefix($0) } ? .service : .tool)
        }
        if isSimulator {
            // iOS bundles are flat; anything else in a simulator is one of its daemons.
            guard own == last - 1 else { return make("\(process) (Simulator)", .service) }
            return make("\(name(components[own])) (Simulator)", .app, bundle(components, upTo: own))
        }
        let outer = apps[0]
        let isSystem = systemRoots.contains { path.hasPrefix($0) }
        return make(name(components[outer]), isSystem ? .service : .app, bundle(components, upTo: outer))
    }

    private static func name(_ component: Substring) -> String {
        String(component.dropLast(".app".count))
    }

    private static func bundle(_ components: [Substring], upTo index: Int) -> String {
        components[...index].joined(separator: "/")
    }
}
