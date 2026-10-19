import AppKit
import Observation
import Testing
import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

private let sampleIcon: Data = NSImage(size: NSSize(width: 4, height: 4), flipped: false) { rect in
    NSColor.red.setFill()
    rect.fill()
    return true
}.tiffRepresentation ?? Data()

@MainActor
@Suite(.tags(.unit))
struct IconStoreTests {
    private let files = FileAccessFake()
    private let preferences = PreferencesFake()
    private let requested = LockedBox<[URL]>([])
    private let cache = URL(fileURLWithPath: "/fake-home/.watcher/favicons")

    private func makeStore(body: Data? = sampleIcon) -> IconStore {
        IconStore(
            preferences: preferences, files: files.access, workspace: WorkspaceOpenerSpy(),
            paths: SupportPaths(directory: URL(fileURLWithPath: "/fake-home/.watcher")),
            homeDirectory: URL(fileURLWithPath: "/fake-home")
        ) { [requested] url in
            requested.mutate { $0.append(url) }
            return body
        }
    }

    @Test
    func aFaviconArrivingRedrawsOnlyItsOwnRow() {
        let store = makeStore()
        let otherRowChanged = ObservationFlag()
        withObservationTracking {
            _ = store.favicon(for: "a.example", fetch: false)
        } onChange: {
            otherRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "b.example")
        #expect(!otherRowChanged.value, "b.example's icon must not invalidate a.example's row")

        let ownRowChanged = ObservationFlag()
        withObservationTracking {
            _ = store.favicon(for: "c.example", fetch: false)
        } onChange: {
            ownRowChanged.set()
        }
        store.setFavicon(NSImage(size: NSSize(width: 16, height: 16)), for: "c.example")
        #expect(ownRowChanged.value, "the row whose icon arrived redraws")
        #expect(store.favicon(for: "c.example", fetch: false) != nil)
    }

    @Test(arguments: [
        ("/Applications/Safari.app", "Safari"), ("/fake-home/Applications/Safari.app", "Safari"),
        ("/System/Applications/Safari.app", "Safari"),
    ])
    func anAppIsFoundInTheApplicationsFolders(bundle: String, process: String) {
        files.write(Data(), to: bundle)
        #expect(makeStore().appIcon(for: process) != nil)
    }

    @Test
    func theNameShownIsKeptForNewRecordsAndCleanedOnlyForLegacyOnes() {
        #expect(IconStore.displayName("Safari & WebKit", isLegacy: false) == "Safari & WebKit")
        #expect(IconStore.displayName("Acme Helper Pro", isLegacy: false) == "Acme Helper Pro")
        #expect(IconStore.displayName("Google Chrome Helper (GPU)", isLegacy: true) == "Google Chrome")
    }

    @Test
    func aCommandLineToolHasNoIcon() {
        #expect(makeStore().appIcon(for: "curl") == nil)
    }

    @Test(arguments: [
        (ClientKind.tool, "terminal"), (.service, "gearshape"), (.device, "iphone"),
    ])
    func toolsServicesAndDevicesGetASymbolWhateverTheyAreCalled(kind: ClientKind, symbol: String) {
        files.write(Data(), to: "/Applications/Safari.app")
        let group = FlowGroup(name: "Safari", count: 1, kind: kind, bundlePath: "/Applications/Safari.app")
        #expect(makeStore().icon(forApp: group.name, kind: group.kind, bundlePath: group.bundlePath) == .symbol(symbol))
    }

    @Test
    func anAppShowsTheIconOfItsBundleWhenKnown() {
        let group = FlowGroup(name: "Whatever", count: 1, kind: .app, bundlePath: "/Elsewhere/Whatever.app")
        guard case .image = makeStore().icon(forApp: group.name, kind: group.kind, bundlePath: group.bundlePath) else {
            Issue.record("expected the bundle's icon")
            return
        }
    }

    private static let simulatorApps = "/fake-home/Library/Developer/CoreSimulator/Devices/D/data/Containers/Bundle/App"

    /// macOS draws an iOS app bundle as a no-entry sign, so a Simulator app shows the icon file its Info.plist names.
    @Test
    func aSimulatorAppShowsTheIconItsInfoPlistNames() throws {
        let bundle = "\(Self.simulatorApps)/Shop.app"
        let plist: [String: Any] = ["CFBundleIcons": ["CFBundlePrimaryIcon": ["CFBundleIconFiles": ["AppIcon60x60"]]]]
        let info = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        files.write(info, to: "\(bundle)/Info.plist")
        files.write(sampleIcon, to: "\(bundle)/AppIcon60x60@2x.png")

        let store = makeStore()
        guard case let .image(icon) = store.icon(forApp: "Shop (Simulator)", kind: .app, bundlePath: bundle) else {
            Issue.record("expected the bundle's own icon")
            return
        }
        #expect(icon.size == NSSize(width: 4, height: 4))
    }

    @Test
    func aSimulatorAppWithoutAnIconFileGetsAnAppSymbol() {
        let bundle = "\(Self.simulatorApps)/Bare.app"
        files.write(Data(), to: "\(bundle)/Bare")
        #expect(makeStore().icon(forApp: "Bare (Simulator)", kind: .app, bundlePath: bundle) == .symbol("app"))
    }

    @Test
    func anAppWithoutABundleIsFoundByNameAndOtherwiseGetsAnAppSymbol() {
        files.write(Data(), to: "/Applications/Safari.app")
        let store = makeStore()
        guard case .image = store.icon(forApp: "Safari & WebKit", kind: .app, bundlePath: nil) else {
            Issue.record("Safari & WebKit takes Safari's icon")
            return
        }
        #expect(store.icon(forApp: "Nothing", kind: .app, bundlePath: nil) == .symbol("app"))
    }

    @Test
    func aHelperProcessShowsItsAppsIcon() {
        files.write(Data(), to: "/Applications/Google Chrome.app")
        #expect(makeStore().appIcon(for: "Google Chrome Helper (Renderer)") != nil)
    }

    @Test
    func aMissingAppIsLookedForOnce() {
        let store = makeStore()
        #expect(store.appIcon(for: "Later") == nil)
        files.write(Data(), to: "/Applications/Later.app")
        #expect(store.appIcon(for: "Later") == nil)
    }

    @Test
    func aFaviconIsDownloadedAndCached() async {
        let store = makeStore()
        _ = store.favicon(for: "site.example")
        #expect(await eventually { store.favicon(for: "site.example", fetch: false) != nil })
        #expect(requested.value == [URL(string: "https://site.example/favicon.ico")])
        #expect(files.contents(of: "\(cache.path)/site.example.ico") == sampleIcon)
    }

    @Test
    func aCachedFaviconIsNotDownloaded() async {
        files.write(sampleIcon, to: "\(cache.path)/site.example.ico")
        let store = makeStore()
        _ = store.favicon(for: "site.example")
        #expect(await eventually { store.favicon(for: "site.example", fetch: false) != nil })
        #expect(requested.value.isEmpty)
    }

    @Test
    func theWwwHostIsTriedWhenTheBareHostHasNoIcon() async {
        let store = makeStore(body: nil)
        _ = store.favicon(for: "site.example")
        #expect(await eventually { requested.value.count == 2 })
        #expect(requested.value.map(\.host) == ["site.example", "www.site.example"])
        #expect(store.favicon(for: "site.example", fetch: false) == nil)
        #expect(files.paths.isEmpty)
    }

    @Test
    func anOversizedOrUndecodableIconIsIgnored() async {
        let store = makeStore(body: Data(repeating: 1, count: 600 * 1024))
        _ = store.favicon(for: "big.example")
        #expect(await eventually { requested.value.count == 2 })
        #expect(files.paths.isEmpty)
    }

    @Test(arguments: ["10.0.0.1", "127.0.0.1", "::1", "fe80::1", "localhost", "my-nas"])
    func anAddressOrSingleLabelHostIsNeverLookedUp(host: String) {
        let store = makeStore()
        _ = store.favicon(for: host)
        #expect(store.requested.isEmpty)
    }

    @Test(arguments: [
        ("Google Chrome Helper (Renderer)", "Google Chrome"),
        ("Slack Helper (GPU)", "Slack"),
        ("Safari Web Content", "Safari"),
        ("com.apple.WebKit.Networking", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("curl", "curl"),
        ("  Firefox  ", "Firefox"),
    ])
    func aProcessNameMapsToItsAppName(process: String, app: String) {
        #expect(IconStore.appName(forProcess: process) == app)
    }

    @Test
    func switchingWebsiteIconsOffFetchesNothing() {
        preferences.websiteIconsEnabled = false
        let store = makeStore()
        _ = store.favicon(for: "site.example")
        #expect(store.requested.isEmpty)
    }

    @Test
    func aSiteIsRequestedOnlyOnce() async {
        let store = makeStore(body: nil)
        _ = store.favicon(for: "site.example")
        _ = store.favicon(for: "site.example")
        #expect(await eventually { requested.value.count == 2 })
        #expect(store.requested == ["site.example"])
    }
}
