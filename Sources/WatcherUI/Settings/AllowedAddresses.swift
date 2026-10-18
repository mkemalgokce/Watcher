/// The allowed-address list as one line of comma separated text, the way the General pane edits it.
enum AllowedAddresses {
    static func text(for addresses: [String]) -> String {
        addresses.joined(separator: ", ")
    }

    static func addresses(in text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}
