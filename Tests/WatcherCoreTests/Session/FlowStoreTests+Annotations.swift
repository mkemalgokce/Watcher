import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension FlowStoreTests {
    struct Annotations {
        private let store = FlowStore()

        @Test
        func starringLeavesTheCommentAlone() {
            let flow = store.begin(.fixture())
            store.annotate(flow.id, comment: "note")
            store.annotate(flow.id, starred: true)
            #expect(store.all.first?.isStarred == true)
            #expect(store.all.first?.comment == "note")
        }

        @Test
        func commentingLeavesTheStarAlone() {
            let flow = store.begin(.fixture())
            store.annotate(flow.id, starred: true)
            store.annotate(flow.id, comment: "note")
            #expect(store.all.first?.isStarred == true)
            #expect(store.all.first?.comment == "note")
        }

        @Test(arguments: [String?.some(""), String?.none])
        func anEmptyOrNilCommentClearsIt(comment: String?) {
            let flow = store.begin(.fixture())
            store.annotate(flow.id, comment: "note")
            store.annotate(flow.id, comment: .some(comment))
            #expect(store.all.first?.comment == nil)
        }

        @Test
        func annotatingAnUnknownFlowChangesNothing() {
            let flow = store.begin(.fixture())
            store.annotate(UUID(), starred: true, comment: "note")
            #expect(store.all.map(\.isStarred) == [false])
            #expect(store.all.map(\.id) == [flow.id])
        }
    }
}
