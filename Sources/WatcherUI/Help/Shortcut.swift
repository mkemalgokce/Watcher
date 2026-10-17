import SwiftUI

/// The shortcut list shown in Help; update it together with the `.keyboardShortcut`s in WatcherCommands.
struct Shortcut {
    let keys: String
    let title: String

    struct Group { let title: String; let items: [Shortcut] }

    static let groups: [Group] = [
        Group(title: "Capture", items: [
            Shortcut(keys: "⌘E", title: "Record or pause (starts and stops the proxy)"),
            Shortcut(keys: "⇧⌘Y", title: "Send this Mac's traffic through Watcher (system proxy)"),
            Shortcut(keys: "⌘K", title: "Clear the session"),
            Shortcut(keys: "⇧⌘D", title: "Set up a phone, simulator or this Mac"),
        ]),
        Group(title: "Find and filter", items: [
            Shortcut(keys: "⌘F", title: "Filter requests"),
            Shortcut(keys: "⌥⌘F", title: "Find in the body"),
            Shortcut(keys: "⌘G", title: "Next match"),
            Shortcut(keys: "⇧⌘G", title: "Previous match"),
            Shortcut(keys: "⇧⌘J", title: "Filter a JSON body with a path or jq"),
            Shortcut(keys: "⇧⌘L", title: "Clear filters"),
            Shortcut(keys: "⌘1 – ⌘4", title: "All requests, Starred, Errors, WebSocket"),
        ]),
        Group(title: "Selected request", items: [
            Shortcut(keys: "⌘R", title: "Repeat"),
            Shortcut(keys: "⌥⌘R", title: "Edit and repeat"),
            Shortcut(keys: "⌘D", title: "Star or unstar"),
            Shortcut(keys: "⇧⌘C", title: "Copy as cURL"),
            Shortcut(keys: "⌥⌘C", title: "Copy URL"),
            Shortcut(keys: "⌥⌘M", title: "Mock this response from a local file"),
            Shortcut(keys: "⇧⌘B", title: "Set as compare base and open Compare"),
            Shortcut(keys: "⌘⌫", title: "Delete"),
        ]),
        Group(title: "Inspector", items: [
            Shortcut(keys: "⌥⌘[", title: "Show the request (narrow inspector)"),
            Shortcut(keys: "⌥⌘]", title: "Show the response (narrow inspector)"),
            Shortcut(keys: "⌃⌘1 – ⌃⌘4", title: "Body as Preview, Pretty, Raw, Hex"),
            Shortcut(keys: "⌥⌘L", title: "Wrap long lines"),
        ]),
        Group(title: "Windows", items: [
            Shortcut(keys: "⌘N", title: "New request (Compose)"),
            Shortcut(keys: "⌥⌘N", title: "New request from the curl command on the clipboard"),
            Shortcut(keys: "⌘B", title: "Breakpoints: paused requests"),
            Shortcut(keys: "⌘T", title: "Tools: Map Local, Block, Scripting…"),
            Shortcut(keys: "⇧⌘U", title: "Converter: Base64, URL, JWT, timestamps"),
            Shortcut(keys: "⌘,", title: "Settings"),
            Shortcut(keys: "⌘/", title: "This help"),
        ]),
        Group(title: "In Compose and Breakpoints", items: [
            Shortcut(keys: "⌘↩", title: "Send, or continue with your edits"),
            Shortcut(keys: "⇧⌘↩", title: "Continue unchanged"),
            Shortcut(keys: "⇧⌘⌫", title: "Abort the paused request"),
            Shortcut(keys: "⎋", title: "Close"),
        ]),
        Group(title: "File", items: [
            Shortcut(keys: "⌘O", title: "Open a session, HAR or Charles file"),
            Shortcut(keys: "⌘S", title: "Save the session"),
            Shortcut(keys: "⇧⌘E", title: "Export HAR"),
        ]),
    ]

    /// "⇧⌘P" read out as "Shift Command P", so VoiceOver does not skip the symbols.
    static func spoken(_ keys: String) -> String {
        let names: [Character: String] = ["⌘": "Command ", "⇧": "Shift ", "⌥": "Option ", "⌃": "Control ", "↩": "Return", "⌫": "Delete", "⎋": "Escape", "–": " to "]
        return keys.map { names[$0] ?? String($0) }.joined()
    }
}
