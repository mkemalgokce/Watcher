import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The whole window in each state a person meets it in: first run, filled, filtered, and in both appearances.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct MainWindowScreenTests {
    static let size = CGSize(width: 1320, height: 780)

    enum State: String, CaseIterable, CustomTestStringConvertible {
        case gettingStarted, populated, selected, filtered, noMatches, errorsOnly

        var testDescription: String {
            rawValue
        }

        @MainActor
        func model() throws -> AppModel {
            switch self {
            case .gettingStarted: return try Screen.model()
            case .populated:
                let model = try Screen.demo()
                model.list.selection = nil
                return model
            case .selected, .filtered, .noMatches, .errorsOnly:
                let model = try Screen.demo()
                model.list.selection = model.list.flows.first?.id
                switch self {
                case .filtered: model.list.query.text = "v1"
                case .noMatches:
                    model.list.query.text = "no such request"
                    model.list.selection = nil
                case .errorsOnly:
                    model.list.sidebar = .errors
                    model.list.selection = model.list.visibleFlows.first?.id
                default: break
                }
                return model
            }
        }
    }

    @Test(arguments: State.allCases)
    func mainWindow(state: State) async throws {
        try await ImageSnapshot.verify(ContentView().environment(state.model()), size: Self.size, named: state.rawValue)
    }

    @Test
    func mainWindowInTheDark() async throws {
        let model = try State.selected.model()
        await ImageSnapshot.verify(
            ContentView().environment(model), size: Self.size, named: "dark", appearance: .darkAqua
        )
    }

    @Test
    func mainWindowWithAnExchangeOfEachKind() async throws {
        let model = try Screen.model(flows: Screen.exchanges, selecting: Screen.users)
        await ImageSnapshot.verify(ContentView().environment(model), size: Self.size, named: "mixed")
    }
}
