import SwiftUI
import WatcherCore

/// What kind of content a request returned, at a glance.
struct ContentKindIcon: View {
    let kind: FlowFilter.ContentKind

    var body: some View {
        let (symbol, name) = switch kind {
        case .json: ("curlybraces", "JSON")
        case .xml: ("chevron.left.forwardslash.chevron.right", "XML")
        case .html: ("doc.richtext", "HTML")
        case .image: ("photo", "Image")
        case .javascript: ("curlybraces.square", "JavaScript")
        case .css: ("paintbrush", "CSS")
        case .form: ("list.bullet.rectangle", "Form")
        case .other: ("doc", "Other")
        }
        Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary).frame(width: 14).help(name).accessibilityLabel(name)
    }
}
