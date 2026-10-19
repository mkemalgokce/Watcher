import Foundation

/// The protobuf descriptor sets named in the settings, and body text decoded with them.
final class ProtobufBodies: @unchecked Sendable {
    private struct Loaded {
        var files: [String] = []
        var schema: ProtobufSchema?
        var hadFailures = false
    }

    private let lock = NSLock()
    private var loaded = Loaded()
    private let files: FileAccess

    init(files: FileAccess) {
        self.files = files
    }

    /// Reads all `.desc` files into one schema; unreadable files are reported and skipped.
    func load(_ paths: [String], log: @Sendable (String) -> Void) {
        let previous = lock.withLock { loaded }
        // A file that failed to load is tried again on the next apply, which runs when the settings change.
        let unchanged = paths == previous.files && !previous.hadFailures && (previous.schema != nil || paths.isEmpty)
        guard !unchanged else { return }
        var combined = Data()
        var hadFailures = false
        for file in paths {
            do { try combined.append(files.read(URL(fileURLWithPath: (file as NSString).expandingTildeInPath)))
                // A FileDescriptorSet is a repeated field, so concatenated sets are themselves a valid set.
            } catch {
                hadFailures = true
                log("Protobuf schema \(file): \(error)")
            }
        }
        let schema = combined.isEmpty ? nil : try? ProtobufSchema(descriptorSet: combined)
        if !paths.isEmpty, schema == nil {
            log("Protobuf schemas could not be parsed")
        }
        lock.withLock { loaded = Loaded(files: paths, schema: schema, hadFailures: hadFailures) }
    }

    /// Body text for display: a schema-decoded protobuf when a rule names the message type, else the generic preview.
    func text(of flow: Flow, response: Bool, rules: [ProtobufRule]) -> String {
        let data = response ? flow.response?.body ?? Data() : flow.request.body
        let headers = response ? flow.response?.headers ?? [] : flow.request.headers
        let contentType = headers.value(for: "content-type")
        let rule = rules.first { $0.matching.compile().matches(flow.request) }
        if let schema = lock.withLock({ loaded.schema }), let rule {
            let type = response ? rule.responseType : rule.requestType
            let message = ProtobufWire.message(in: data, contentType: contentType)
            if !type.isEmpty, let text = schema.describe(message, as: type) {
                return text
            }
        }
        return BodyPreview.text(data, contentType: contentType)
    }
}
