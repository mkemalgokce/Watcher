import Testing
@testable import WatcherCore
@testable import WatcherUI

@Suite(.tags(.unit))
struct SidebarItemTests {
    @Test(arguments: [
        (FlowGroup(name: "Chrome", count: 1, kind: .app), "Chrome"),
        (FlowGroup(name: "Chrome", count: 1, kind: .app, processes: ["Chrome"]), "Chrome"),
        (FlowGroup(name: "Chrome", count: 1, kind: .app, processes: ["Chrome", "Helper"]), "Chrome: Helper"),
        (FlowGroup(name: "trustd", count: 1, kind: .service, processes: ["trustd"]), "trustd"),
        (FlowGroup(name: "Chrome Helper", count: 1, kind: .app), "Chrome"),
    ])
    func theTooltipListsTheRawProcessesOnlyWhenTheyDiffer(group: FlowGroup, tooltip: String) {
        #expect(group.tooltip == tooltip)
    }
}
