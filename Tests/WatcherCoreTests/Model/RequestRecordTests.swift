import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct RequestRecordTests {
    @Test
    func requestsSavedBeforeClientAppExistedStillDecode() throws {
        let json = #"{"method":"GET","scheme":"http","host":"a","port":80,"path":"/","headers":[],"body":""}"#
        let request = try JSONDecoder().decode(RequestRecord.self, from: Data(json.utf8))
        #expect(request.clientApp == nil)
    }
}
