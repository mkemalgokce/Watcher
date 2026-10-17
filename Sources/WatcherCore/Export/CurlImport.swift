import Foundation

/// Reads a `curl …` command (as copied from a browser's dev tools, docs or a terminal) back into a request.
public enum CurlImport {
    public struct Failure: Error, CustomStringConvertible, Equatable {
        public let description: String
    }

    /// Whether `text` looks like a curl command, so a pasted one can be recognised without trying to parse every URL.
    public static func looksLikeCurl(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("curl ") || trimmed.hasPrefix("curl\t") || trimmed.hasPrefix("curl\\")
    }

    /// Options whose value is the next word, and which do not change the request (output, TLS, timeouts…).
    private static let ignoredWithValue: Set<String> = [
        "-o", "--output", "-x", "--proxy", "--cacert", "--capath", "-E", "--cert", "--key", "-m", "--max-time", "--connect-timeout",
        "-w", "--write-out", "-c", "--cookie-jar", "--retry", "--resolve", "--interface", "-r", "--range", "--limit-rate", "-U", "--proxy-user",
        "-D", "--dump-header", "--trace", "--trace-ascii", "--cert-type", "--key-type", "--ciphers", "--max-redirs",
    ]

    public static func parse(_ command: String) throws -> RequestRecord {
        var words = try tokenize(command)
        guard words.first == "curl" else { throw Failure(description: "This is not a curl command.") }
        words.removeFirst()

        var method: String?
        var url: String?
        var headers: [Header] = []
        var data: [String] = []
        var asQuery = false
        var head = false
        var index = 0

        func value(for option: String) throws -> String {
            index += 1
            guard index < words.count else { throw Failure(description: "\(option) needs a value.") }
            return words[index]
        }

        while index < words.count {
            var word = words[index]
            var inline: String?
            // --header=value and the like.
            if word.hasPrefix("--"), let equals = word.firstIndex(of: "=") {
                inline = String(word[word.index(after: equals)...]); word = String(word[..<equals])
            }
            func argument() throws -> String {
                try inline ?? value(for: word)
            }

            switch word {
            case "-X", "--request": method = try argument().uppercased()
            case "-H", "--header":
                let line = try argument()
                guard let colon = line.firstIndex(of: ":") else { break } // "-H 'Name;'" style empty headers are dropped
                headers.append(Header(
                    String(line[..<colon]).trimmingCharacters(in: .whitespaces),
                    String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                ))
            case "-d", "--data", "--data-raw", "--data-binary", "--data-ascii", "--data-urlencode", "--json":
                let part = try argument()
                if word != "--data-raw", part.hasPrefix("@") {
                    throw Failure(description: "Bodies read from a file (\(part)) are not supported; paste the body itself.")
                }
                data.append(word == "--data-urlencode" ? urlEncodedPair(part) : part)
                if word == "--json" {
                    if headers.value(for: "content-type") == nil {
                        headers.append(Header("Content-Type", "application/json"))
                    }
                    if headers.value(for: "accept") == nil {
                        headers.append(Header("Accept", "application/json"))
                    }
                }
            case "-b", "--cookie": try headers.append(Header("Cookie", argument()))
            case "-u", "--user": try headers.append(Header("Authorization", "Basic " + Data(argument().utf8).base64EncodedString()))
            case "-A", "--user-agent": try headers.append(Header("User-Agent", argument()))
            case "-e", "--referer": try headers.append(Header("Referer", argument()))
            case "-I", "--head": head = true
            case "-G", "--get": asQuery = true
            case "--url": url = try argument()
            case "--compressed":
                if headers.value(for: "accept-encoding") == nil {
                    headers.append(Header("Accept-Encoding", "gzip, deflate, br"))
                }
            default:
                if ignoredWithValue.contains(word) {
                    _ = try argument()
                } else if word.hasPrefix("-"), word.count > 1 {
                    break
                } // -s, -L, -k, -v, -i and other switches without a value
                else if url == nil {
                    url = word
                }
            }
            index += 1
        }

        guard let url, !url.isEmpty else { throw Failure(description: "The command has no URL.") }
        let address = url.contains("://") ? url : "http://" + url // curl assumes http:// too
        guard var components = URLComponents(string: address), let host = components.host, !host.isEmpty,
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme)
        else {
            throw Failure(description: "“\(url)” is not an http or https URL.")
        }
        var body = Data(data.joined(separator: "&").utf8)
        if asQuery, !data.isEmpty {
            let existing = components.percentEncodedQuery.map { $0 + "&" } ?? ""
            components.percentEncodedQuery = existing + data.joined(separator: "&")
            body = Data()
        }
        let resolvedMethod = method ?? (head ? "HEAD" : (body.isEmpty ? "GET" : "POST"))
        if !body.isEmpty, headers.value(for: "content-type") == nil {
            headers.append(Header("Content-Type", "application/x-www-form-urlencoded")) // what curl itself sends with -d
        }
        let path = (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath) + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        return RequestRecord(
            method: resolvedMethod,
            scheme: scheme,
            host: host,
            port: components.port ?? (scheme == "https" ? 443 : 80),
            path: path,
            headers: headers,
            body: body
        )
    }

    /// `name=value` with the value percent-encoded, as `--data-urlencode` does; a bare value is encoded whole.
    private static func urlEncodedPair(_ part: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed; allowed.remove(charactersIn: "&=+")
        guard let equals = part.firstIndex(of: "=") else { return part.addingPercentEncoding(withAllowedCharacters: allowed) ?? part }
        let name = part[..<equals], value = part[part.index(after: equals)...]
        return name + "=" + (String(value).addingPercentEncoding(withAllowedCharacters: allowed) ?? String(value))
    }

    /// Splits like a POSIX shell (plus bash's `$'…'`): quotes group words, `\` escapes, a backslash-newline continues the line.
    static func tokenize(_ command: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var characters = Array(command)[...]

        while let character = characters.popFirst() {
            switch character {
            case "'":
                inWord = true
                guard let end = characters.firstIndex(of: "'") else { throw Failure(description: "A single quote is not closed.") }
                current += String(characters[..<end]); characters = characters[(end + 1)...]
            case "\"":
                inWord = true
                var closed = false
                while let next = characters.popFirst() {
                    if next == "\"" {
                        closed = true; break
                    }
                    if next == "\\", let escaped = characters.first, "\"\\$`\n".contains(escaped) {
                        characters.removeFirst()
                        if escaped != "\n" {
                            current.append(escaped)
                        }
                    } else {
                        current.append(next)
                    }
                }
                guard closed else { throw Failure(description: "A double quote is not closed.") }
            case "$" where characters.first == "'":
                inWord = true
                characters.removeFirst()
                current += try ansiC(&characters)
            case "\\":
                guard let escaped = characters.popFirst() else { break }
                if escaped == "\n" || escaped == "\r" { // line continuation
                    if escaped == "\r", characters.first == "\n" {
                        characters.removeFirst()
                    }
                } else {
                    inWord = true; current.append(escaped)
                }
            case " ", "\t", "\n", "\r":
                if inWord {
                    words.append(current); current = ""; inWord = false
                }
            default:
                inWord = true; current.append(character)
            }
        }
        if inWord {
            words.append(current)
        }
        return words
    }

    /// The body of a `$'…'` word, with its backslash escapes resolved.
    private static func ansiC(_ characters: inout ArraySlice<Character>) throws -> String {
        var result = ""
        while let character = characters.popFirst() {
            if character == "'" {
                return result
            }
            guard character == "\\", let escape = characters.popFirst() else { result.append(character); continue }
            switch escape {
            case "n": result.append("\n")
            case "t": result.append("\t")
            case "r": result.append("\r")
            case "0": result.append("\0")
            case "x":
                let hex = String(characters.prefix(2).prefix { $0.isHexDigit })
                characters.removeFirst(hex.count)
                if let value = UInt8(hex, radix: 16) {
                    result.append(Character(Unicode.Scalar(value)))
                }
            case "u":
                let hex = String(characters.prefix(4).prefix { $0.isHexDigit })
                characters.removeFirst(hex.count)
                if let value = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(value) {
                    result.append(Character(scalar))
                }
            default: result.append(escape) // \\ \' \" and anything else stand for themselves
            }
        }
        throw Failure(description: "A $' quote is not closed.")
    }
}
