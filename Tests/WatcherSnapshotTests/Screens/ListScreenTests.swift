import Foundation
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The request list and the sidebar on their own, at the width they have in the window.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct ListScreenTests {
    private static let listSize = CGSize(width: 760, height: 420)

    @Test
    func theListOfTraffic() async throws {
        let model = try Screen.demo()
        await ImageSnapshot.verify(FlowListView().environment(model), size: Self.listSize, named: "populated")
    }

    @Test
    func theListWithAStarredAndCommentedRequest() async throws {
        var starred = Screen.users
        starred.isStarred = true
        starred.comment = "creates the account"
        let model = try Screen.model(flows: [starred, Screen.image, Screen.failed], selecting: Screen.image)
        await ImageSnapshot.verify(FlowListView().environment(model), size: Self.listSize, named: "starred")
    }

    @Test
    func theListWhileFiltered() async throws {
        let model = try Screen.demo()
        model.list.query.text = "login"
        await ImageSnapshot.verify(FlowListView().environment(model), size: Self.listSize, named: "filtered")
    }

    @Test
    func theListWithNoMatches() async throws {
        let model = try Screen.demo()
        model.list.query.text = "no such request"
        await ImageSnapshot.verify(FlowListView().environment(model), size: Self.listSize, named: "noMatches")
    }

    @Test
    func theListBeforeAnyTraffic() async throws {
        try await ImageSnapshot.verify(FlowListView().environment(Screen.model()), size: Self.listSize, named: "empty")
    }

    @Test
    func theSidebar() async throws {
        let model = try Screen.model(flows: Screen.exchanges)
        await ImageSnapshot.verify(
            SidebarView().environment(model), size: CGSize(width: 240, height: 520), named: "populated"
        )
    }

    @Test
    func theSidebarWithEveryKindOfClient() async throws {
        try await ImageSnapshot.verify(
            SidebarView().environment(Screen.demo()), size: CGSize(width: 240, height: 520), named: "clients"
        )
    }

    @Test
    func theSidebarWithItsSystemServicesOpen() async throws {
        let model = try Screen.demo()
        model.list.expandsSystemServices = true
        await ImageSnapshot.verify(
            SidebarView().environment(model), size: CGSize(width: 240, height: 520), named: "servicesOpen"
        )
    }

    @Test
    func theSidebarBeforeAnyTraffic() async throws {
        try await ImageSnapshot.verify(
            SidebarView().environment(Screen.model()), size: CGSize(width: 240, height: 320), named: "empty"
        )
    }
}
