import Foundation

/// Turns a captured request into runnable code.
public enum CodeGenerator {
    public enum Language: String, CaseIterable, Sendable {
        case curl = "cURL", swift = "Swift (URLSession)", python = "Python (requests)", javascript = "JavaScript (fetch)"
        case go = "Go (net/http)", ruby = "Ruby (Net::HTTP)", php = "PHP (cURL)"
    }

    /// A body as each language should write it: readable text when it is UTF-8, otherwise the exact bytes.
    enum Body {
        case none, text(String), binary(Data)

        init(_ data: Data) {
            if data.isEmpty {
                self = .none
            } else if let text = String(data: data, encoding: .utf8) {
                self = .text(text)
            } else {
                self = .binary(data)
            }
        }
    }

    /// `proxy` (e.g. `http://127.0.0.1:9090`) adds `-x` to cURL so the command goes through Watcher again;
    /// `certificate` is Watcher's root CA file, added as `--cacert` so such an HTTPS command trusts Watcher.
    /// `multiline` puts each cURL option on its own line, joined with backslashes, so long commands can be read.
    public static func generate(_ request: RequestRecord, as language: Language, proxy: String? = nil, certificate: String? = nil, multiline: Bool = false) -> String {
        let headers = request.headers.filter { !["host", "content-length", "connection", "proxy-connection"].contains($0.name.lowercased()) }
        let body = Body(request.body)
        switch language {
        case .curl: return curl(request, headers, body, proxy: proxy, certificate: certificate, multiline: multiline)
        case .swift: return swift(request, headers, body)
        case .python: return python(request, headers, body)
        case .javascript: return javascript(request, headers, body)
        case .go: return go(request, headers, body)
        case .ruby: return ruby(request, headers, body)
        case .php: return php(request, headers, body)
        }
    }

    private static func curl(_ request: RequestRecord, _ headers: [Header], _ body: Body, proxy: String?, certificate: String?, multiline: Bool) -> String {
        var parts = ["curl"]
        let method = request.method.uppercased()
        if case .none = body, method == "GET" {
            // curl's default; nothing to say.
        } else if method == "HEAD" {
            parts.append("--head") // -X HEAD makes curl wait for a body that never comes
        } else if method == "POST", !request.body.isEmpty {
            // --data already makes it a POST.
        } else {
            parts += ["-X", request.method]
        }
        parts.append(shellQuote(request.url))
        if let proxy {
            parts += ["-x", shellQuote(proxy)]
            if request.scheme == "https", let certificate {
                parts += ["--cacert", shellQuote(certificate)]
            }
        }
        var compressed = false
        for header in headers {
            // curl only decodes what it asked for itself; a copied Accept-Encoding would print compressed bytes.
            if header.name.caseInsensitiveCompare("accept-encoding") == .orderedSame {
                compressed = true; continue
            }
            parts += ["-H", shellQuote("\(header.name): \(header.value)")]
        }
        if compressed {
            parts.append("--compressed")
        }
        // An option and its value stay together on one line.
        func join(_ parts: [String]) -> String {
            guard multiline else { return parts.joined(separator: " ") }
            var lines: [String] = []
            for part in parts {
                if let last = lines.last, last == "curl" || (last.hasPrefix("-") && !last.contains(" ")), !part.hasPrefix("-") {
                    lines[lines.count - 1] += " " + part
                } else {
                    lines.append(part)
                }
            }
            return lines.joined(separator: " \\\n  ")
        }
        switch body {
        case .none: return join(parts)
        case let .text(text): return join(parts + ["--data-raw", shellQuote(text)])
        case let .binary(data):
            // Shell arguments cannot hold NUL bytes, so the exact bytes are piped in through POSIX printf.
            return "printf '%b' \(printfEscaped(data)) | " + join(parts + ["--data-binary", "@-"])
        }
    }

    private static func swift(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        var lines = ["var request = URLRequest(url: URL(string: \(literal(request.url)))!)", "request.httpMethod = \(literal(request.method))"]
        lines += headers.map { "request.setValue(\(literal($0.value)), forHTTPHeaderField: \(literal($0.name)))" }
        switch body {
        case .none: break
        case let .text(text): lines.append("request.httpBody = Data(\(literal(text)).utf8)")
        case let .binary(data): lines.append("request.httpBody = Data(base64Encoded: \(literal(data.base64EncodedString())))!")
        }
        lines.append("let (data, response) = try await URLSession.shared.data(for: request)")
        return lines.joined(separator: "\n")
    }

    private static func python(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        var lines = ["import requests"]
        if case .binary = body {
            lines.append("import base64")
        }
        lines += ["", "response = requests.request(", "    \(literal(request.method)),", "    \(literal(request.url)),"]
        if !headers.isEmpty {
            lines.append("    headers={" + headers.map { "\(literal($0.name)): \(literal($0.value))" }.joined(separator: ", ") + "},")
        }
        switch body {
        case .none: break
        case let .text(text): lines.append("    data=\(literal(text)),")
        case let .binary(data): lines.append("    data=base64.b64decode(\(literal(data.base64EncodedString()))),")
        }
        lines += [")", "print(response.status_code, response.text)"]
        return lines.joined(separator: "\n")
    }

    private static func javascript(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        var options = ["  method: \(literal(request.method)),"]
        if !headers.isEmpty {
            options.append("  headers: {" + headers.map { "\(literal($0.name)): \(literal($0.value))" }.joined(separator: ", ") + "},")
        }
        switch body {
        case .none: break
        case let .text(text): options.append("  body: \(literal(text)),")
        case let .binary(data): options.append("  body: Uint8Array.from(atob(\(literal(data.base64EncodedString()))), c => c.charCodeAt(0)),")
        }
        return "const response = await fetch(\(literal(request.url)), {\n\(options.joined(separator: "\n"))\n});\nconsole.log(response.status, await response.text());"
    }

    private static func go(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        // Go refuses to compile unused imports, so each body kind imports only what it uses.
        let reader: String, imports: [String], setup: [String]
        switch body {
        case .none:
            (reader, imports, setup) = ("nil", [], [])
        case let .text(text):
            (reader, imports, setup) = ("strings.NewReader(\(literal(text)))", ["strings"], [])
        case let .binary(data):
            (reader, imports, setup) = (
                "bytes.NewReader(payload)",
                ["bytes", "encoding/base64"],
                ["\tpayload, _ := base64.StdEncoding.DecodeString(\(literal(data.base64EncodedString())))"]
            )
        }
        var lines = ["package main", "", "import ("] + (imports + ["fmt", "io", "net/http"]).sorted().map { "\t\"\($0)\"" } + [")", "", "func main() {"]
        lines += setup
        lines.append("\treq, _ := http.NewRequest(\(literal(request.method)), \(literal(request.url)), \(reader))")
        lines += headers.map { "\treq.Header.Set(\(literal($0.name)), \(literal($0.value)))" }
        lines += ["\tres, err := http.DefaultClient.Do(req)", "\tif err != nil { panic(err) }", "\tdefer res.Body.Close()", "\tout, _ := io.ReadAll(res.Body)", "\tfmt.Println(res.StatusCode, string(out))", "}"]
        return lines.joined(separator: "\n")
    }

    private static func ruby(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        /// `#` is escaped because Ruby interpolates "#{...}" inside double quotes.
        func quoted(_ text: String) -> String {
            literal(text).replacingOccurrences(of: "#", with: "\\#")
        }
        var lines = ["require 'net/http'"]
        if case .binary = body {
            lines.append("require 'base64'")
        }
        lines += ["", "uri = URI(\(quoted(request.url)))", "request = Net::HTTP::\(request.method.capitalized).new(uri)"]
        lines += headers.map { "request[\(quoted($0.name))] = \(quoted($0.value))" }
        switch body {
        case .none: break
        case let .text(text): lines.append("request.body = \(quoted(text))")
        case let .binary(data): lines.append("request.body = Base64.strict_decode64(\(quoted(data.base64EncodedString())))")
        }
        lines += ["response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https') { |http| http.request(request) }", "puts response.code, response.body"]
        return lines.joined(separator: "\n")
    }

    private static func php(_ request: RequestRecord, _ headers: [Header], _ body: Body) -> String {
        /// Single quotes: PHP would interpolate `$name` inside double quotes.
        func quoted(_ text: String) -> String {
            "'" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'") + "'"
        }
        var lines = ["<?php", "$ch = curl_init(\(quoted(request.url)));", "curl_setopt($ch, CURLOPT_CUSTOMREQUEST, \(quoted(request.method)));", "curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);"]
        if !headers.isEmpty {
            lines.append("curl_setopt($ch, CURLOPT_HTTPHEADER, [" + headers.map { quoted("\($0.name): \($0.value)") }.joined(separator: ", ") + "]);")
        }
        switch body {
        case .none: break
        case let .text(text): lines.append("curl_setopt($ch, CURLOPT_POSTFIELDS, \(quoted(text)));")
        case let .binary(data): lines.append("curl_setopt($ch, CURLOPT_POSTFIELDS, base64_decode(\(quoted(data.base64EncodedString()))));")
        }
        lines += ["echo curl_exec($ch);", "curl_close($ch);"]
        return lines.joined(separator: "\n")
    }

    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A single-quoted argument for POSIX `printf '%b'`: printable ASCII as is, every other byte (and `\` and `'`) as `\0ooo`.
    static func printfEscaped(_ data: Data) -> String {
        var out = "'"
        for byte in data {
            if (0x20 ... 0x7E).contains(byte), byte != UInt8(ascii: "\\"), byte != UInt8(ascii: "'") {
                out.append(Character(Unicode.Scalar(byte)))
            } else {
                out += "\\0" + String(byte, radix: 8).leftPadded(to: 3)
            }
        }
        return out + "'"
    }

    /// JSON string literal, valid in all four target languages.
    private static func literal(_ text: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [text]), encoding: .utf8))
            .map { String($0.dropFirst().dropLast()).replacingOccurrences(of: "\\/", with: "/") } ?? "\"\""
    }
}

private extension String {
    func leftPadded(to length: Int) -> String {
        String(repeating: "0", count: max(0, length - count)) + self
    }
}
