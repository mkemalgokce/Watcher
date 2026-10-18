import UniformTypeIdentifiers

enum FileExtension {
    /// "json" for "application/json; charset=utf-8"; nil when the type is missing or unknown.
    static func preferred(forContentType contentType: String?) -> String? {
        let media = contentType?.split(separator: ";").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return media.isEmpty ? nil : UTType(mimeType: media)?.preferredFilenameExtension
    }
}
