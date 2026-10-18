import ApplicationServices

/// The system accessibility API, pointed at this process: what UI automation and VoiceOver use. Inside one process the
/// requests are answered directly on the calling thread, so they run on the main thread like the UI they inspect.
@MainActor
enum AccessibilityAPI {
    private static let searchLimit = 5000

    /// Every element of this process whose title, description or value is `label`.
    static func find(_ label: String) -> [AXUIElement] {
        let app = AXUIElementCreateApplication(getpid())
        AXUIElementSetMessagingTimeout(app, 5)
        return elements { element in
            [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute].contains { attribute in
                string(attribute, of: element) == label
            }
        }
    }

    static func canPress(_ element: AXUIElement) -> Bool {
        var actions: CFArray?
        AXUIElementCopyActionNames(element, &actions)
        return (actions as? [String])?.contains(kAXPressAction as String) == true
    }

    static func press(_ element: AXUIElement) -> AXError {
        AXUIElementPerformAction(element, kAXPressAction as CFString)
    }

    /// The first element with `role` whose current value starts with `prefix`.
    static func firstElement(withRole role: String, valuePrefix prefix: String) -> AXUIElement? {
        elements(stoppingAtFirst: true) { element in
            string(kAXRoleAttribute, of: element) == role
                && (string(kAXValueAttribute, of: element) ?? "").hasPrefix(prefix)
        }.first
    }

    static func setValue(_ text: String, of element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, text as CFString) == .success
    }

    /// The role of the process's first window, which is "AXWindow" when the service answers properly.
    static func firstWindowRole() -> String? {
        windows().first.flatMap { string(kAXRoleAttribute, of: $0) }
    }

    private static func windows() -> [AXUIElement] {
        var windows: CFTypeRef?
        AXUIElementCopyAttributeValue(AXUIElementCreateApplication(getpid()), kAXWindowsAttribute as CFString, &windows)
        return windows as? [AXUIElement] ?? []
    }

    /// Walks the element tree of every window breadth first, as far as `searchLimit` elements.
    private static func elements(stoppingAtFirst: Bool = false, where matches: (AXUIElement) -> Bool) -> [AXUIElement] {
        var found: [AXUIElement] = [], queue = windows(), visited = 0
        while !queue.isEmpty, visited < searchLimit {
            let element = queue.removeFirst()
            visited += 1
            if matches(element) {
                found.append(element)
                if stoppingAtFirst {
                    return found
                }
            }
            var children: CFTypeRef?
            if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &children) == .success {
                queue += children as? [AXUIElement] ?? []
            }
        }
        return found
    }

    private static func string(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
