import SwiftUI
import Testing
@testable import WatcherCore
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ToolbarTests {
        private func mainWindowModel() throws -> AppModel {
            let model = try AppModel.demo(sleep: liveSleep)
            model.onboardingDone = true
            return model
        }

        /// Nothing is captured until Record; Record starts a real listener and Pause stops it, with the status bar
        /// following along. A free port is picked and the system proxy is a spy, so this cannot clash with a running
        /// Watcher or change the Mac's network.
        @Test
        func recordStartsAndPauseStopsTheProxy() async throws {
            let engine = try WatcherEngine.inMemory()
            let model = try AppModel(dependencies: .test(engine: engine, runner: engine))
            model.onboardingDone = true
            try model.useFreePort(searchingFrom: 20000, fallback: 29999)
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                #expect(await !eventually(timeout: 0.5) { model.proxy.isRunning }, "the proxy waits for Record")

                try await window.press("Record")
                #expect(await eventually { model.proxy.isRunning && !model.proxy.isSwitchingProxy })
                #expect(model.proxy.isRunning)
                #expect(model.notices.notice?.kind == .success)
                let address = "127.0.0.1:\(model.engine.boundPort ?? 0)"
                #expect(
                    await eventually { model.statusLine.hasPrefix("Recording on \(address)") },
                    "the status bar shows the address"
                )

                try await window.press("Pause")
                #expect(await eventually { !model.proxy.isRunning && !model.proxy.isSwitchingProxy })
                #expect(!model.proxy.isRunning, "pausing stops the proxy")
                #expect(model.notices.notice?.message == "Recording paused; the proxy is off")
                #expect(model.statusLine.hasPrefix("Not recording"))
            }
        }

        @Test(arguments: [
            ("Compose", AppModel.Sheet.compose),
            ("Breakpoints", .breakpoints),
            ("Tools", .tools),
        ])
        func toolbarOpensTheScreen(label: String, sheet: AppModel.Sheet) async throws {
            let model = try mainWindowModel()
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                model.router.sheet = nil
                #expect(await window.shows(label), "\(label) is in the toolbar")
                try await window.press(label)
                #expect(model.router.sheet == sheet, "\(label)")
            }
        }

        @Test
        func moreMenuHoldsTheRestOfTheToolbar() async throws {
            let model = try mainWindowModel()
            await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                model.router.sheet = nil
                #expect(
                    await window.shows("More"),
                    "Start/Stop, converter, devices and shortcuts sit in the More menu"
                )
            }
        }

        @Test
        func toolbarClearEmptiesTheListAndUndoBringsItBack() async throws {
            let model = try mainWindowModel()
            model.observeEngine() // the list follows the store only while observing it
            try await withWindow(showing: ContentView().environment(model), width: 1320, height: 780) { window in
                let before = model.engine.store.all.map(\.id)
                #expect(!before.isEmpty)

                try await window.press("Clear")
                #expect(await eventually { model.list.flows.isEmpty })
                #expect(model.engine.store.all.isEmpty)
                try await window.press("Undo")
                #expect(await eventually { model.list.flows.count == before.count })
                #expect(model.engine.store.all.map(\.id) == before)
            }
        }
    }
}
