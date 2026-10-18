import AppKit
import SwiftUI
import Testing
import WatcherTestSupport
@testable import WatcherUI

extension InteractionTests {
    @MainActor
    struct ImagePreviewTests {
        private static func pixel() throws -> Data {
            let rep = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            return try #require(rep.representation(using: .png, properties: [:]))
        }

        @Test
        func savingTheImageWritesItThroughTheSessionFiles() async throws {
            let target = URL(fileURLWithPath: "/fake-home/out/image.png")
            let panels = FilePanelsStub(save: target), files = FileAccessFake()
            let model = try AppModel(dependencies: .test(panels: panels, files: files))
            let png = try Self.pixel()
            let view = ImagePreview(data: png, mime: "image/png").environment(model)
            try await withWindow(showing: view, width: 500, height: 300) { window in
                try await window.press("Save Image…")
                #expect(await eventually { panels.saveRequests.map(\.suggestedName) == ["image.png"] })
                #expect(await eventually { files.contents(of: target.path) == png })
                #expect(await eventually { model.notices.notice?.kind == .success })
            }
        }
    }
}
