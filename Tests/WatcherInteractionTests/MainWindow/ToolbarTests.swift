import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ToolbarTests {
        private func mainWindowModel() -> AppModel {
            let model = AppModel.preview()
            model.onboardingDone = true
            return model
        }

        /// Nothing is captured until Record; Record starts the proxy and Pause stops it, with the status bar following
        /// along. A free port is picked, and test settings never turn on the system proxy, so this cannot clash with a
        /// running Watcher or change the Mac's network.
        @Test
        func recordStartsAndPauseStopsTheProxy() async throws {
            let model = AppModel(listening: false)
            model.onboardingDone = true
            try model.useFreePort(searchingFrom: 20000, fallback: 29999)
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                await settle(1)
                #expect(!model.isRunning, "the proxy waits for Record")

                try await window.press("Record")
                #expect(await eventually { model.isRunning && !model.isSwitchingProxy })
                #expect(model.isRunning)
                #expect(model.notice?.kind == .success)
                await settle()
                let address = "127.0.0.1:\(model.engine.boundPort ?? 0)"
                #expect(model.statusLine.hasPrefix("Recording on \(address)"), "the status bar shows the address")

                try await window.press("Pause")
                #expect(await eventually { !model.isRunning && !model.isSwitchingProxy })
                #expect(!model.isRunning, "pausing stops the proxy")
                #expect(model.notice?.message == "Recording paused; the proxy is off")
                #expect(model.statusLine.hasPrefix("Not recording"))
            }
        }

        @Test(arguments: [
            ("Compose", AppModel.Sheet.compose),
            ("Breakpoints", .breakpoints),
            ("Tools", .tools),
        ])
        func toolbarOpensTheScreen(label: String, sheet: AppModel.Sheet) async throws {
            let model = mainWindowModel()
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                model.sheet = nil
                await settle(0.3)
                try await window.press(label)
                #expect(model.sheet == sheet, "\(label)")
            }
        }

        @Test
        func moreMenuHoldsTheRestOfTheToolbar() async {
            let model = mainWindowModel()
            await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                model.sheet = nil
                await settle(0.3)
                #expect(
                    !window.elements("More").isEmpty,
                    "Start/Stop, converter, devices and shortcuts sit in the More menu"
                )
            }
        }

        @Test
        func toolbarClearEmptiesTheListAndUndoBringsItBack() async throws {
            let model = mainWindowModel()
            model.observeEngine() // the list follows the store only while observing it
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                let before = model.engine.store.all.map(\.id)
                #expect(!before.isEmpty)

                try await window.press("Clear")
                #expect(await eventually { model.flows.isEmpty })
                #expect(model.engine.store.all.isEmpty)
                try await window.press("Undo")
                #expect(await eventually { model.flows.count == before.count })
                #expect(model.engine.store.all.map(\.id) == before)
            }
        }
    }
}
