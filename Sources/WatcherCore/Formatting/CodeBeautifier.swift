import Foundation

/// Indents brace-style code (minified JavaScript, CSS) so it can be read. It is a layout aid, not a parser: it understands strings,
/// comments and parentheses well enough not to break `for (;;)` headers or URLs, and leaves everything else alone.
public enum CodeBeautifier {
    public static func beautify(_ source: String, indent: Int = 2) -> String {
        var output = "", depth = 0, parentheses = 0
        var quote: Character?, escaped = false, lineComment = false, blockComment = false
        let unit = String(repeating: " ", count: indent)
        let characters = Array(source)
        let hasBraces = source.contains("{")

        func newline() {
            while output.last == " " {
                output.removeLast()
            }
            output += "\n" + String(repeating: unit, count: max(0, depth))
        }
        var index = 0
        while index < characters.count {
            let c = characters[index], next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
            if lineComment {
                output.append(c); if c == "\n" {
                    lineComment = false; output += String(repeating: unit, count: depth)
                }; index += 1; continue
            }
            if blockComment {
                output.append(c); if c == "*", next == "/" {
                    output.append("/"); index += 1; blockComment = false
                }; index += 1; continue
            }
            if let q = quote {
                output.append(c)
                if escaped {
                    escaped = false
                } else if c == "\\" {
                    escaped = true
                } else if c == q {
                    quote = nil
                }
                index += 1; continue
            }
            switch c {
            case "\"", "'", "`": quote = c; output.append(c)
            case "/" where next == "/": lineComment = true; output.append(c)
            case "/" where next == "*": blockComment = true; output.append(c)
            case "(": parentheses += 1; output.append(c)
            case ")": parentheses = max(0, parentheses - 1); output.append(c)
            case "{": if output.last != " ", output.last != "\n", !output.isEmpty {
                    output.append(" ")
                }; output.append(c); depth += 1; newline()
            case "}": depth = max(0, depth - 1); newline(); output.append(c)
                if let n = next, n != ";", n != ",", n != ")", n != "." {
                    newline()
                }
            case ";" where parentheses == 0: output.append(c); newline()
            case ",": output.append(c); if parentheses == 0, depth > 0, hasBraces {
                    newline()
                } else {
                    output.append(" ")
                }
            case "\n", "\r", "\t": if output.last != " ", output.last != "\n", !output.isEmpty {
                    output.append(" ")
                }
            case " ": if output.last != " ", output.last != "\n", !output.isEmpty {
                    output.append(c)
                }
            default: output.append(c)
            }
            index += 1
        }
        return output.split(separator: "\n", omittingEmptySubsequences: true).map { String($0).replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n")
    }
}
