import AppKit
import UniformTypeIdentifiers

struct LiveFilePanels: FilePanels {
    @MainActor func chooseItem(directory: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directory
        panel.canChooseDirectories = directory
        return panel.runModal() == .OK ? panel.url : nil
    }

    @MainActor func chooseSaveLocation(suggestedName: String, contentTypes: [UTType]) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        if !contentTypes.isEmpty {
            panel.allowedContentTypes = contentTypes
        }
        return panel.runModal() == .OK ? panel.url : nil
    }
}
