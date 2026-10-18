import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport

extension RequestRecordTests {
    struct CacheValidators {
        @Test(arguments: ["If-None-Match", "if-modified-since", "IF-NONE-MATCH"])
        func validatorsAreDroppedInAnyLetterCase(name: String) {
            let request = RequestRecord.fixture(headers: [Header(name, "x")]).droppingCacheValidators()
            #expect(request.headers.value(for: name) == nil)
        }

        @Test
        func existingCacheHeadersAreReplacedAndOthersKept() {
            let request = RequestRecord.fixture(headers: [
                Header("Accept", "*/*"), Header("cache-control", "max-age=60"), Header("PRAGMA", "x"),
            ]).droppingCacheValidators()
            #expect(request.headers == [
                Header("Accept", "*/*"), Header("Cache-Control", "no-cache, no-store"), Header("Pragma", "no-cache"),
            ])
        }
    }
}
