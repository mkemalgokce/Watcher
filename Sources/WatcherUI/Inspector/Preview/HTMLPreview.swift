import SwiftUI
import WebKit

/// Renders an HTML response the way a browser would, but offline: JavaScript is off and every network load is blocked,
/// so looking at a page never contacts its servers or runs its scripts.
struct HTMLPreview: NSViewRepresentable {
    let html: String

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setAccessibilityLabel("Rendered HTML")
        OfflineHTML.load(
            html,
            blockNetwork: { done in Self.blockNetwork(in: view, done) },
            show: { view.loadHTMLString($0, baseURL: nil) }
        )
        return view
    }

    private static func blockNetwork(in view: WKWebView, _ done: @escaping @MainActor (Bool) -> Void) {
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "watcher.block-all",
            encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        ) { list, _ in
            MainActor.assumeIsolated {
                if let list {
                    view.configuration.userContentController.add(list)
                }
                done(list != nil)
            }
        }
    }

    func updateNSView(_: WKWebView, context _: Context) {}
}
