import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct NoCachingToolTests {
    private func intercepted(_ headers: [Header]) async -> RequestRecord {
        var request = RequestRecord.fixture(headers: headers)
        _ = await NoCachingTool().intercept(request: &request)
        return request
    }

    @Test(arguments: ["If-None-Match", "if-none-match", "IF-MODIFIED-SINCE", "If-Modified-Since"])
    func cacheValidatorsAreRemovedWhateverTheirCase(name: String) async {
        let request = await intercepted([Header(name, "x"), Header("Accept", "*/*")])
        #expect(request.headers.value(for: name) == nil)
        #expect(request.headers.value(for: "Accept") == "*/*")
    }

    @Test
    func freshResponsesAreAskedFor() async {
        let request = await intercepted([])
        #expect(request.headers.value(for: "Cache-Control") == "no-cache, no-store")
        #expect(request.headers.value(for: "Pragma") == "no-cache")
    }

    @Test
    func existingCacheControlIsReplacedNotDuplicated() async {
        let request = await intercepted([Header("cache-control", "max-age=60")])
        let values = request.headers.filter { $0.name.lowercased() == "cache-control" }.map(\.value)
        #expect(values == ["no-cache, no-store"])
    }

    @Test
    func theRequestIsAlwaysForwarded() async {
        var request = RequestRecord.fixture()
        guard case .forward = await NoCachingTool().intercept(request: &request) else {
            Issue.record("expected forward"); return
        }
    }
}
