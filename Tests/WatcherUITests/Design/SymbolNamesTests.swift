import AppKit
import Testing
import WatcherTestSupport

/// A misspelled or unavailable SF Symbol draws nothing and fails silently, so every name in the UI sources must exist.
@Suite(.tags(.unit))
struct SymbolNamesTests {
    @Test
    func everySymbolNameExists() throws {
        let pattern = try NSRegularExpression(pattern: #"(?:systemImage|systemName|symbol)\s*[:(]\s*([^,\n]*)"#)
        let name = try NSRegularExpression(pattern: #""([a-z][a-z0-9]*(?:\.[a-z0-9]+)+)""#)
        var missing: Set<String> = []
        let enumerator = FileManager.default.enumerator(at: SourceTree.url("Sources"), includingPropertiesForKeys: nil)
        let files = enumerator?.compactMap { $0 as? URL } ?? []
        for file in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                let argument = (text as NSString).substring(with: match.range(at: 1))
                for found in name.matches(in: argument, range: NSRange(argument.startIndex..., in: argument)) {
                    let symbol = (argument as NSString).substring(with: found.range(at: 1))
                    if NSImage(systemSymbolName: symbol, accessibilityDescription: nil) == nil {
                        missing.insert("\(symbol) in \(file.lastPathComponent)")
                    }
                }
            }
        }
        #expect(missing.isEmpty, "unknown SF Symbols: \(missing.sorted())")
    }
}
