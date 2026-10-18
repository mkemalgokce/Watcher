import SwiftUI
import WatcherCore

struct FilePreview: View {
    let field: FormField

    var body: some View {
        if let data = field.data {
            if field.contentType?.lowercased().hasPrefix("image/") == true || Base64Finder.imageMime(data) != nil {
                ImagePreview(data: data, mime: field.contentType)
            } else if let text = String(data: data.prefix(200_000), encoding: .utf8), !text.contains("\u{0}") {
                SyntaxTextView(text, language: BodyLanguage.detect(contentType: field.contentType, data: data))
            } else {
                SyntaxTextView(BodyFormatter.hexDump(data, limit: 4096), language: .binary, wraps: false)
            }
        }
    }
}
