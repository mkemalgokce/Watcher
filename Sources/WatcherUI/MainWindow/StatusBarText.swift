import WatcherCore

/// The wording of the status bar and the toolbar badges, apart from the views that show it.
enum StatusBarText {
    struct HTTPS: Equatable {
        let text: String
        let decryptsAll: Bool
    }

    static func https(_ ssl: SSLProxyingSettings) -> HTTPS {
        let includesAll = ssl.include.contains("*")
        if includesAll, ssl.exclude.isEmpty {
            return HTTPS(text: "HTTPS decrypted", decryptsAll: true)
        }
        if includesAll {
            return HTTPS(text: "HTTPS: all but \(hosts(ssl.exclude.count))", decryptsAll: false)
        }
        let text = ssl.include.isEmpty ? "HTTPS: not decrypted" : "HTTPS: \(hosts(ssl.include.count))"
        return HTTPS(text: text, decryptsAll: false)
    }

    /// One tool by its name, several as a count.
    static func tools(_ names: [String]) -> String {
        names.count == 1 ? names[0] : "\(names.count) tools on"
    }

    static func toolRulesHelp(_ count: Int) -> String {
        switch count {
        case 0: "Map Local, Block List, Scripting and the other tools (⌘T)"
        case 1: "1 tool rule is changing traffic (⌘T)"
        default: "\(count) tool rules are changing traffic (⌘T)"
        }
    }

    private static func hosts(_ count: Int) -> String {
        count == 1 ? "1 host" : "\(count) hosts"
    }
}
