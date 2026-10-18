import Observation
import WatcherCore

/// The converter's input, chosen operation and result; the result follows either one as it changes.
@MainActor @Observable
final class ConverterViewModel {
    var input = "" {
        didSet { run() }
    }

    var operation = Converter.Operation.base64Decode {
        didSet { run() }
    }

    private(set) var output = ""
    private(set) var failure: String?

    /// Shown only for real work: blank input converts to nothing, so it is not "converted".
    var isConverted: Bool {
        failure == nil && !isBlank
    }

    private var isBlank: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ObservationIgnored private let convert: (Converter.Operation, String) throws -> String

    init(convert: @escaping (Converter.Operation, String) throws -> String = { try Converter.run($0, $1) }) {
        self.convert = convert
    }

    /// Only on request: reading the clipboard by itself shows a paste-permission prompt and can pick up private text.
    func paste(from clipboard: any Clipboard) {
        input = clipboard.string() ?? input
    }

    func useResultAsInput() {
        input = output
    }

    private func run() {
        guard !isBlank else {
            output = ""; failure = nil
            return
        }
        do {
            output = try convert(operation, input); failure = nil
        } catch {
            output = ""; failure = "\(error)"
        }
    }
}
