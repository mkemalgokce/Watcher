import Foundation
import Observation
import UniformTypeIdentifiers
import WatcherCore

/// Saving, exporting and opening session files. Encoding, decoding and disk access run off the main thread, so a large
/// session does not freeze the window.
@MainActor @Observable
final class SessionFilesViewModel {
    /// Set while a session file is read or written.
    private(set) var busyMessage: String?

    @ObservationIgnored private let panels: any FilePanels
    @ObservationIgnored private let files: FileAccess
    @ObservationIgnored private let commands: CommandRunner
    @ObservationIgnored private let store: FlowStore
    @ObservationIgnored private let notices: NoticeCenter

    init(
        panels: any FilePanels,
        files: FileAccess,
        commands: @escaping CommandRunner,
        store: FlowStore,
        notices: NoticeCenter
    ) {
        self.panels = panels; self.files = files; self.commands = commands
        self.store = store; self.notices = notices
    }

    func exportHAR() {
        save(name: "session.har", type: .json) { try HAR.export($0) }
    }

    func exportCSV() {
        save(name: "session.csv", type: .commaSeparatedText) { CSVExporter.export($0) }
    }

    func saveSession() {
        save(name: "session.watcher", type: .json) { try SessionFile.encode($0) }
    }

    func importFile() {
        guard let url = panels.chooseItem(directory: false) else { return }
        Task { await importFile(at: url) }
    }

    func importFile(at url: URL) async {
        guard isFree else { return }
        let name = url.lastPathComponent
        busyMessage = "Opening \(name)…"
        defer { busyMessage = nil }
        do {
            let flows = try await read(url)
            store.load(flows)
            if flows.isEmpty {
                notices.notify("\(name) has no requests")
            } else {
                notices.notify("Opened \(flows.count) requests from \(name)", .success)
            }
        } catch { notices.notify("Cannot open \(name): \(error)", .error) }
    }

    /// Save panel for a body or a decoded payload, then writes it off the main thread.
    func saveData(_ data: Data, suggestedName: String) {
        guard let url = panels.chooseSaveLocation(suggestedName: suggestedName, contentTypes: []) else { return }
        let files = files
        Task {
            do {
                try await Task.detached(priority: .userInitiated) { try files.writeAtomically(data, url) }.value
                notices.notify("Saved \(url.lastPathComponent) (\(Format.bytes(data.count)))", .success)
            } catch { notices.notify("Cannot save \(url.lastPathComponent): \(error)", .error) }
        }
    }

    /// Saves the decoded body of one side under the name `ExchangeText` suggests.
    func saveBody(of flow: Flow, side: MessageSide) {
        let name = ExchangeText.suggestedFileName(for: flow, side: side)
        saveData(ExchangeText.body(of: flow, side: side), suggestedName: name)
    }

    private func read(_ url: URL) async throws -> [Flow] {
        let files = files
        switch url.pathExtension.lowercased() {
        case "chls", "chlz":
            // Binary sessions are converted by an installed Charles.
            return try await CharlesConverter.flows(from: url, runner: commands, files: files)
        case let ext:
            return try await Task.detached(priority: .userInitiated) {
                let data = try files.read(url)
                switch ext {
                case "har": return try HAR.flows(from: data)
                case "chlsj": return try CharlesSession.flows(from: data)
                default: return try SessionFile.decode(data)
                }
            }.value
        }
    }

    /// One session file at a time: a second would clear the first one's progress message while it still runs.
    private var isFree: Bool {
        guard busyMessage != nil else { return true }
        notices.notify("Wait for the current file to finish.", .error)
        return false
    }

    private func save(name: String, type: UTType, encode: @escaping @Sendable ([Flow]) throws -> Data) {
        guard isFree, let url = panels.chooseSaveLocation(suggestedName: name, contentTypes: [type]) else { return }
        let flows = store.all
        busyMessage = "Saving \(url.lastPathComponent)…"
        Task { await write(flows, to: url, encode) }
    }

    private func write(_ flows: [Flow], to url: URL, _ encode: @escaping @Sendable ([Flow]) throws -> Data) async {
        defer { busyMessage = nil }
        let files = files
        do {
            try await Task.detached(priority: .userInitiated) { try files.writeAtomically(encode(flows), url) }.value
            notices.notify("Saved \(flows.count) requests to \(url.lastPathComponent)", .success)
        } catch { notices.notify("Cannot save \(url.lastPathComponent): \(error)", .error) }
    }
}
