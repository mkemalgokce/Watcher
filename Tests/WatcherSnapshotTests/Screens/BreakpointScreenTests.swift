import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

/// The Breakpoints window with its rules, and with requests and responses waiting for a decision.
@MainActor
@Suite(
    .tags(.snapshot, .ui),
    .enabled(if: ImageSnapshot.canRun(), "no references for this macOS and recording is off")
)
struct BreakpointScreenTests {
    private static let size = CGSize(width: 960, height: 620)

    private func model(paused: Bool) throws -> AppModel {
        let model = try Screen.model()
        model.settings.breakpoints = RuleSet(
            isEnabled: true,
            rules: [
                BreakpointRule(matching: MatchingRule(pattern: "api.example.com/v1/login")),
                BreakpointRule(matching: MatchingRule(pattern: "api.example.com/v1/me")),
            ]
        )
        if paused {
            let since = Screen.started.addingTimeInterval(-12)
            model.breakpoints.hits = [
                .init(
                    phase: .request,
                    request: .fixture(
                        method: "POST", url: "https://api.example.com/v1/login",
                        headers: [Header("Content-Type", "application/json")],
                        body: Screen.json(#"{"user":"ada","password":"secret"}"#)
                    ),
                    pausedAt: since
                ),
                .init(
                    phase: .response,
                    request: .fixture(url: "https://api.example.com/v1/me"),
                    response: .fixture(
                        status: 200, headers: [Header("Content-Type", "application/json")],
                        body: Screen.json(#"{"id":42,"plan":"free"}"#)
                    ),
                    pausedAt: since
                ),
            ]
        }
        return model
    }

    @Test
    func rulesWithNothingWaiting() async throws {
        let model = try model(paused: false)
        await ImageSnapshot.verify(BreakpointsView().environment(model), size: Self.size, named: "idle")
    }

    @Test
    func requestsWaitingForADecision() async throws {
        let model = try model(paused: true)
        await ImageSnapshot.verify(BreakpointsView().environment(model), size: Self.size, named: "paused")
    }
}
