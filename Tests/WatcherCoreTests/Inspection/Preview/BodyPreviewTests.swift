import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BodyPreviewTests {
    @Test
    func previewsGraphQLAndGRPC() {
        let body = Data(#"{"operationName":"GetUser","query":"query GetUser { me { id } }","variables":{"id":1}}"#.utf8)
        let graphQL = BodyPreview.text(body, contentType: "application/json")
        #expect(graphQL.hasPrefix("# operation: GetUser") && graphQL.contains("# variables"), "\(graphQL)")
        let grpc = Data([0, 0, 0, 0, 2, 0x08, 0x07])
        #expect(BodyPreview.text(grpc, contentType: "application/grpc") == "1: 7")
    }
}
