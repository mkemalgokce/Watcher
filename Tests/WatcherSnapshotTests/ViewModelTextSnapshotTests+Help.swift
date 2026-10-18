import SnapshotTesting
import Testing
@testable import WatcherUI

extension ViewModelTextSnapshotTests {
    /// The shortcut list in Help, which must stay in step with the menus.
    struct Help {
        @Test
        func everyShortcutGroup() {
            let text = Shortcut.groups.map { group in
                ([group.title] + group.items.map { "  \($0.keys)  \($0.title)" }).joined(separator: "\n")
            }
            assertSnapshot(of: text.joined(separator: "\n"), as: .lines)
        }
    }
}
