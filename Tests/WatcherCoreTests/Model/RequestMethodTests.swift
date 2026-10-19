import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RequestMethodTests {
    @Test
    func theCommonMethodsAreUniqueAndUppercase() {
        #expect(Set(RequestMethod.common).count == RequestMethod.common.count)
        #expect(RequestMethod.common.allSatisfy { $0 == $0.uppercased() })
        #expect(RequestMethod.common.first == "GET")
    }
}
