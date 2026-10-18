import SwiftUI
import WebKit

/// Renders an HTML response the way a browser would, but offline: JavaScript is off and every network load is blocked,
/// so looking at a page never contacts its servers or runs its scripts.
struct HTMLPreview: NSViewRepresentable {
    let html: String
    var compileRules = OfflineHTML.liveCompiler

    func makeNSView(context _: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setAccessibilityLabel("Rendered HTML")
        OfflineHTML.load(
            html,
            blockNetwork: { done in
                let controller = view.configuration.userContentController
                OfflineHTML.blockNetwork(in: controller, compile: compileRules, done: done)
            },
            show: { view.loadHTMLString($0, baseURL: nil) }
        )
        return view
    }

    func updateNSView(_: WKWebView, context _: Context) {}
}
