import Foundation

/// One editable row of headers, query parameters or form fields. Disabled rows are kept in the editor but not sent.
public struct KeyValue: Identifiable, Hashable, Sendable {
    public var id = UUID()
    public var name: String
    public var value: String
    public var isEnabled = true
    /// For multipart rows: a file instead of text.
    public var file: FilePart?

    public struct FilePart: Hashable, Sendable {
        public var filename: String
        public var contentType: String
        public var data: Data
        public init(filename: String, contentType: String, data: Data) {
            self.filename = filename; self.contentType = contentType; self.data = data
        }
    }

    public init(_ name: String = "", _ value: String = "", isEnabled: Bool = true, file: FilePart? = nil) {
        self.name = name; self.value = value; self.isEnabled = isEnabled; self.file = file
    }

    var isSendable: Bool {
        isEnabled && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
