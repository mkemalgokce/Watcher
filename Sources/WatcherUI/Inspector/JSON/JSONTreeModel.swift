import Observation
import WatcherCore

/// Which containers of a JSON document are open, and so which nodes are listed. Folding is the only state here;
/// reading the document is `JSONTree`'s job and drawing it is the view's.
@MainActor @Observable
final class JSONTreeModel {
    let tree: JSONTree
    private(set) var expanded: Set<Int>
    private(set) var rows: [Int] = []

    init(tree: JSONTree) {
        self.tree = tree
        expanded = tree.defaultExpanded()
        refreshRows()
    }

    func isExpanded(_ index: Int) -> Bool {
        expanded.contains(index)
    }

    func toggle(_ index: Int) {
        guard tree.nodes[index].isExpandable else { return }
        if !expanded.insert(index).inserted {
            expanded.remove(index)
        }
        refreshRows()
    }

    func expandAll() {
        expanded = Set(tree.nodes.indices.filter { tree.nodes[$0].isExpandable })
        refreshRows()
    }

    func collapseAll() {
        expanded = []
        refreshRows()
    }

    func expandSubtree(_ index: Int) {
        expanded.formUnion(tree.expandableNodes(in: index))
        refreshRows()
    }

    func collapseSubtree(_ index: Int) {
        expanded.subtract(tree.expandableNodes(in: index))
        refreshRows()
    }

    private func refreshRows() {
        rows = tree.visibleRows(expanded: expanded)
    }
}
