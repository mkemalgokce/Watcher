import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension RequestRecordTests {
    @Test
    func requestsSavedBeforeClientKindsExistedKeepTheirAppAndHaveNoKind() throws {
        let json = #"{"method":"GET","scheme":"http","host":"a","port":80,"path":"/","headers":[],"body":"","#
            + #""clientApp":"Safari"}"#
        let request = try JSONDecoder().decode(RequestRecord.self, from: Data(json.utf8))
        #expect(request.clientApp == "Safari")
        #expect(request.clientProcess == nil && request.clientKind == nil && request.clientBundlePath == nil)
    }

    @Test
    func attributingARequestStoresTheWholeIdentityAndItSurvivesARoundTrip() throws {
        var request = RequestRecord.fixture()
        let slack = "/Applications/Slack.app"
        request.attribute(to: ClientIdentity(app: "Slack", process: "Slack Helper", kind: .app, bundlePath: slack))
        #expect(request.clientApp == "Slack" && request.clientProcess == "Slack Helper")
        #expect(request.clientKind == .app && request.clientBundlePath == slack)
        let decoded = try JSONDecoder().decode(RequestRecord.self, from: JSONEncoder().encode(request))
        #expect(decoded == request)
    }
}
