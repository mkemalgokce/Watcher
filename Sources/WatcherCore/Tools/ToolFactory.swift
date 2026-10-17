import Foundation

/// Builds the ordered tool pipeline from settings. Order matters: gatekeepers first, then rewriters, then observers.
enum ToolFactory {
    static func makeTools(
        from settings: WatcherSettings,
        breakpoints: BreakpointCenter,
        log: @escaping @Sendable (String) -> Void
    ) -> [Tool] {
        var tools: [Tool] = []
        let allow = settings.allowList.active
        if !allow.isEmpty {
            tools.append(AllowListTool(rules: allow))
        }
        let block = settings.blockList.active
        if !block.isEmpty {
            tools.append(BlockListTool(rules: block))
        }
        let remote = settings.mapRemote.active
        if !remote.isEmpty {
            tools.append(MapRemoteTool(rules: remote))
        }
        let local = settings.mapLocal.active
        if !local.isEmpty {
            tools.append(MapLocalTool(rules: local))
        }
        if settings.noCaching {
            tools.append(NoCachingTool())
        }
        let scripts = settings.scripting.active
        if !scripts.isEmpty {
            tools.append(ScriptTool(rules: scripts, log: log))
        }
        let hits = settings.breakpoints.active
        if !hits.isEmpty {
            tools.append(BreakpointTool(rules: hits, center: breakpoints))
        }
        if settings.throttle.isEnabled {
            tools.append(ThrottleTool(settings: settings.throttle))
        }
        return tools
    }
}
