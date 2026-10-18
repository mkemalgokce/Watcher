import Foundation

extension [Header] {
    /// Reads `[{"name": …, "value": …}]`, skipping entries that lack either.
    init(jsonList value: Any?) {
        self = (value as? [[String: Any]] ?? []).compactMap {
            guard let name = $0["name"] as? String, let value = $0["value"] as? String else { return nil }
            return Header(name, value)
        }
    }
}
