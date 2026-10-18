import Testing
@testable import WatcherCore
import WatcherTestSupport

@Suite(.tags(.unit))
struct BreakpointTemplateTests {
    @Test
    func builtInTemplatesComeFirstAndCustomOnesFollow() throws {
        let templates = WatcherSettings().allBreakpointTemplates
        #expect(templates.map(\.status) == [401, 404, 429, 500, 503])
        let tooMany = try #require(templates.first { $0.status == 429 })
        #expect(tooMany.headers.value(for: "retry-after") == "60")
        #expect(tooMany.body == #"{"error":"too_many_requests"}"#)
        var settings = WatcherSettings()
        settings.breakpointTemplates = [BreakpointTemplate(name: "Teapot", status: 418)]
        #expect(settings.allBreakpointTemplates.last?.name == "Teapot")
    }
}
