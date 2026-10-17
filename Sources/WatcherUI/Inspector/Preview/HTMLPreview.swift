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
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "watcher.block-all",
            encodedContentRuleList: #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
        ) { list, _ in
            if let list {
                view.configuration.userContentController.add(list)
            }
            view.loadHTMLString(html, baseURL: nil)
        }
        return view
    }

    func updateNSView(_: WKWebView, context _: Context) {}
}
