import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct ClientIdentityClassificationTests {
    private struct Case {
        let process: String
        let path: String?
        let app: String
        let kind: ClientKind
        let bundle: String?
    }

    private static let chrome = "/Applications/Google Chrome.app"
    private static let code = "/Applications/Visual Studio Code.app"
    private static let derived = "/Users/me/DerivedData/MyApp-abc/Build/Products/Debug/MyApp.app"
    private static let simulator = "/Users/me/Library/Developer/CoreSimulator/Devices/ABC/data/Containers/Bundle/App/U1"
    private static let runtime = "/Library/Developer/CoreSimulator/Volumes/iOS/Runtime/RuntimeRoot"
    private static let cryptexes = "/System/Volumes/Preboot/Cryptexes"
    private static let shared = "Safari & WebKit"
    private static let webKit = "com.apple.WebKit.Networking"
    private static let xpc = "/WebKit.framework/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/" + webKit

    private static let table = [
        Case(
            process: "Google Chrome Helper (Renderer)",
            path: chrome + "/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/"
                + "Google Chrome Helper (Renderer).app/Contents/MacOS/Google Chrome Helper (Renderer)",
            app: "Google Chrome", kind: .app, bundle: chrome
        ),
        Case(
            process: "Code Helper (Plugin)",
            path: code + "/Contents/Frameworks/Code Helper (Plugin).app/Contents/MacOS/Code Helper (Plugin)",
            app: "Visual Studio Code", kind: .app, bundle: code
        ),
        Case(
            process: "Slack", path: "/Applications/Slack.app/Contents/MacOS/Slack",
            app: "Slack", kind: .app, bundle: "/Applications/Slack.app"
        ),
        Case(process: "MyApp", path: derived + "/Contents/MacOS/MyApp", app: "MyApp", kind: .app, bundle: derived),
        Case(
            process: "MyApp", path: simulator + "/MyApp.app/MyApp",
            app: "MyApp (Simulator)", kind: .app, bundle: simulator + "/MyApp.app"
        ),
        Case(
            process: "MobileSafari", path: runtime + "/Applications/MobileSafari.app/MobileSafari",
            app: "MobileSafari (Simulator)", kind: .app, bundle: runtime + "/Applications/MobileSafari.app"
        ),
        Case(
            process: "nsurlsessiond", path: runtime + "/usr/libexec/nsurlsessiond",
            app: "nsurlsessiond (Simulator)", kind: .service, bundle: nil
        ),
        Case(
            process: "nsurlsessiond", path: "/usr/libexec/nsurlsessiond",
            app: "nsurlsessiond", kind: .service, bundle: nil
        ),
        Case(
            process: "mDNSResponder", path: "/usr/sbin/mDNSResponder",
            app: "mDNSResponder", kind: .service, bundle: nil
        ),
        Case(
            process: "Siri", path: "/System/Library/CoreServices/Siri.app/Contents/MacOS/Siri",
            app: "Siri", kind: .service, bundle: "/System/Library/CoreServices/Siri.app"
        ),
        Case(
            process: "Safari", path: cryptexes + "/App/System/Applications/Safari.app/Contents/MacOS/Safari",
            app: "Safari", kind: .app, bundle: cryptexes + "/App/System/Applications/Safari.app"
        ),
        Case(
            process: "Notes", path: "/System/Applications/Notes.app/Contents/MacOS/Notes",
            app: "Notes", kind: .app, bundle: "/System/Applications/Notes.app"
        ),
        Case(process: webKit, path: "/System/Library/Frameworks" + xpc, app: shared, kind: .app, bundle: nil),
        Case(process: webKit, path: cryptexes + "/OS/System/Library" + xpc, app: shared, kind: .app, bundle: nil),
        Case(process: webKit, path: nil, app: shared, kind: .app, bundle: nil),
        Case(process: "curl", path: "/usr/bin/curl", app: "curl", kind: .tool, bundle: nil),
        Case(process: "node", path: "/opt/homebrew/bin/node", app: "node", kind: .tool, bundle: nil),
        Case(
            process: "xcodebuild", path: "/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild",
            app: "xcodebuild", kind: .tool, bundle: nil
        ),
        Case(process: "trustd", path: nil, app: "trustd", kind: .service, bundle: nil),
        Case(
            process: "Agent", path: "/Library/Apple/System/Library/CoreServices/Agent.app/Contents/MacOS/Agent",
            app: "Agent", kind: .service, bundle: "/Library/Apple/System/Library/CoreServices/Agent.app"
        ),
        Case(
            process: "Helper", path: "/usr/libexec/Helper.app/Contents/MacOS/Helper",
            app: "Helper", kind: .service, bundle: "/usr/libexec/Helper.app"
        ),
        Case(
            process: "Mail Agent", path: cryptexes + "/OS/System/Library/CoreServices/MailAgent.app/Contents/MacOS/x",
            app: "MailAgent", kind: .service, bundle: cryptexes + "/OS/System/Library/CoreServices/MailAgent.app"
        ),
        Case(
            process: "FlatAgent", path: "/System/Library/CoreServices/FlatAgent.app/FlatAgent",
            app: "FlatAgent", kind: .service, bundle: "/System/Library/CoreServices/FlatAgent.app"
        ),
        Case(process: "launchd", path: "/sbin/launchd", app: "launchd", kind: .service, bundle: nil),
        Case(
            process: "assistantd", path: "/System/Library/PrivateFrameworks/A.framework/assistantd",
            app: "assistantd", kind: .service, bundle: nil
        ),
        Case(process: "oahd", path: "/Library/Apple/usr/libexec/oah/oahd", app: "oahd", kind: .service, bundle: nil),
        Case(
            process: "Flat", path: "/Applications/Flat.app/Flat",
            app: "Flat", kind: .app, bundle: "/Applications/Flat.app"
        ),
    ]

    @Test(arguments: table)
    private func classifiesAProcessByItsExecutablePath(_ row: Case) {
        #expect(
            ClientIdentity.classify(process: row.process, executablePath: row.path)
                == ClientIdentity(app: row.app, process: row.process, kind: row.kind, bundlePath: row.bundle)
        )
    }
}
