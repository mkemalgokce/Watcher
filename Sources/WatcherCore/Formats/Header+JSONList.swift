import Foundation

extension [Header] {
    /// Reads `[{"name": …, "value": …}]`, skipping entries that lack either.
    init(jsonList value: Any?) {
        self = (value as? [Any] ?? []).compactMap { entry in
            guard let object = entry as? [String: Any], let name = object["name"] as? String,
                  let value = object["value"] as? String else { return nil }
            return Header(name, value)
        }
    }
}
