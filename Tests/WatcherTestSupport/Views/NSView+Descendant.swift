import AppKit

public extension NSView {
    /// This view or the first of its subviews, depth first, that is a `T`.
    func firstDescendant<T: NSView>(of _: T.Type) -> T? {
        if let match = self as? T {
            return match
        }
        for subview in subviews {
            if let found = subview.firstDescendant(of: T.self) {
                return found
            }
        }
        return nil
    }
}
