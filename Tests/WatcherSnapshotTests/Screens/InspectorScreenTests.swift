import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The inspector for each kind of exchange, with the tabs each side is showing.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct InspectorScreenTests {
    private static let size = CGSize(width: 1100, height: 640)

    struct Scene: CustomTestStringConvertible, Sendable {
        let name: String
        let flow: Flow
        var request = MessagePanel.Section.body
        var response = MessagePanel.Section.body

        var testDescription: String {
            name
        }
    }

    static let scenes = [
        Scene(name: "jsonBody", flow: Screen.users, request: .params),
        Scene(name: "requestBody", flow: Screen.users),
        Scene(name: "headers", flow: Screen.users, request: .headers, response: .headers),
        Scene(name: "cookies", flow: Screen.users, request: .cookies, response: .cookies),
        Scene(name: "raw", flow: Screen.users, request: .raw, response: .raw),
        Scene(name: "image", flow: Screen.image),
        Scene(name: "failed", flow: Screen.failed),
        Scene(name: "webSocket", flow: Screen.webSocket, response: .messages),
        Scene(name: "embeddedData", flow: Screen.embedded, response: .decoded),
        Scene(name: "jsonTree", flow: Screen.nestedJSON),
        Scene(name: "yamlTree", flow: Screen.yaml),
        Scene(name: "formWithJSON", flow: Screen.formWithJSON, request: .params),
    ]

    private func inspector(_ scene: Scene) throws -> some View {
        let model = try Screen.model(flows: [scene.flow], selecting: scene.flow)
        model.viewer.choose(scene.request, for: .request)
        model.viewer.choose(scene.response, for: .response)
        return FlowDetailView().environment(model)
    }

    @Test(arguments: scenes)
    func inspector(scene: Scene) async throws {
        try await ImageSnapshot.verify(inspector(scene), size: Self.size, named: scene.name)
    }

    @Test
    func inspectorInTheDark() async throws {
        let scene = Self.scenes[0]
        try await ImageSnapshot.verify(inspector(scene), size: Self.size, named: "dark", appearance: .darkAqua)
    }

    @Test
    func inspectorInANarrowColumn() async throws {
        let scene = Self.scenes[0]
        try await ImageSnapshot.verify(inspector(scene), size: CGSize(width: 520, height: 640), named: "narrow")
    }

    @Test
    func inspectorWithNothingSelected() async throws {
        try await ImageSnapshot.verify(
            FlowDetailView().environment(Screen.model()), size: CGSize(width: 520, height: 400), named: "none"
        )
    }
}
