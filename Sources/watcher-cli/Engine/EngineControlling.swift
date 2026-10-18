import WatcherCore

/// The part of the engine `start` and `mcp` drive; tests pass one that opens no socket.
protocol EngineControlling: AnyObject, Sendable {
    var store: FlowStore { get }
    var breakpoints: BreakpointCenter { get }
    var settings: SettingsStore { get }
    var onLog: @Sendable (String) -> Void { get set }
    /// Returns the port actually bound.
    func start(port: Int?) async throws -> Int
    func stop() async throws
    func apply(_ settings: WatcherSettings) async
    /// Answers one MCP line about this engine; nil for a notification.
    func mcpHandler() -> @Sendable (String) async -> String?
}

extension WatcherEngine: EngineControlling {
    func mcpHandler() -> @Sendable (String) async -> String? {
        let server = MCPServer(engine: self)
        return { await server.handle($0) }
    }
}
