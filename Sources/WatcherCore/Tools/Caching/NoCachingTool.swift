/// Forces fresh responses by stripping validators and disabling caches.
struct NoCachingTool: Tool {
    let name = "No Caching"

    func intercept(request: inout RequestRecord) async -> RequestDecision {
        request = request.droppingCacheValidators()
        return .forward
    }
}
