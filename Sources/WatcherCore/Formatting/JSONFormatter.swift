import Foundation

/// Re-indents JSON without parsing it into dictionaries, so key order and number spelling survive.
/// Works on UTF-8 bytes in one pass, which keeps tens of megabytes within a second or two.
public enum JSONFormatter {
    /// Pretty-prints `text`; text that is not JSON-shaped is returned unchanged.
    public static func pretty(_ text: String, indent: Int = 2) -> String {
        guard looksLikeJSON(text) else { return text }
        return String(decoding: prettyData(Data(text.utf8), indent: indent), as: UTF8.self)
    }

    public static func prettyData(_ data: Data, indent: Int = 2) -> Data {
        rewrite(data) { source, out in
            var depth = 0, inString = false, escaped = false, i = 0
            let n = source.count
            func newline() {
                out.append(0x0A); out.append(contentsOf: repeatElement(0x20, count: depth * indent))
            }
            while i < n {
                let c = source[i]
                if inString {
                    out.append(c)
                    if escaped {
                        escaped = false
                    } else if c == 0x5C {
                        escaped = true
                    } else if c == 0x22 {
                        inString = false
                    }
                } else {
                    switch c {
                    case 0x22: inString = true; out.append(c)
                    case 0x7B, 0x5B: // { [
                        let closing: UInt8 = c == 0x7B ? 0x7D : 0x5D
                        var peek = i + 1
                        while peek < n, isSpace(source[peek]) {
                            peek += 1
                        }
                        if peek < n, source[peek] == closing {
                            out.append(c); out.append(closing); i = peek
                        } // keep {} and [] on one line
                        else {
                            out.append(c); depth += 1; newline()
                        }
                    case 0x7D, 0x5D: depth = max(0, depth - 1); newline(); out.append(c)
                    case 0x2C: out.append(c); newline()
                    case 0x3A: out.append(0x3A); out.append(0x20)
                    case 0x20, 0x0A, 0x0D, 0x09: break
                    default: out.append(c)
                    }
                }
                i += 1
            }
        }
    }

    /// Removes insignificant whitespace.
    public static func minify(_ text: String) -> String {
        guard looksLikeJSON(text) else { return text }
        return String(decoding: minifyData(Data(text.utf8)), as: UTF8.self)
    }

    public static func minifyData(_ data: Data) -> Data {
        rewrite(data) { source, out in
            var inString = false, escaped = false
            for c in source {
                if inString {
                    out.append(c)
                    if escaped {
                        escaped = false
                    } else if c == 0x5C {
                        escaped = true
                    } else if c == 0x22 {
                        inString = false
                    }
                } else if c == 0x22 {
                    inString = true; out.append(c)
                } else if !isSpace(c) {
                    out.append(c)
                }
            }
        }
    }

    /// The same document with object keys sorted (parsed and re-serialized, so key order of the original is lost).
    public static func sortedKeys(_ data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let sorted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed, .withoutEscapingSlashes]) else { return nil }
        return String(data: sorted, encoding: .utf8)
    }

    static func looksLikeJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }
        return "{[\"-0123456789".contains(first) || ["true", "false", "null"].contains(trimmed)
    }

    private static func isSpace(_ c: UInt8) -> Bool {
        c == 0x20 || c == 0x0A || c == 0x0D || c == 0x09
    }

    private static func rewrite(_ data: Data, _ body: (UnsafeRawBufferPointer, inout [UInt8]) -> Void) -> Data {
        var out = [UInt8]()
        out.reserveCapacity(data.count + data.count / 2)
        data.withUnsafeBytes { body($0, &out) }
        return Data(out)
    }
}
