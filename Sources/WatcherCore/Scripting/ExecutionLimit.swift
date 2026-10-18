import JavaScriptCore

/// Stops synchronous JavaScript that runs past the timeout, which no promise or queue can interrupt.
/// The limit is JavaScriptCore SPI (JSContextRefPrivate.h), so it is looked up at run time.
enum ExecutionLimit {
    private typealias SetLimit = @convention(c) (
        JSContextGroupRef, Double, OpaquePointer?, UnsafeMutableRawPointer?
    ) -> Void

    // shortcut: without the symbol an endless loop runs on (script calls still time out); upgrade to a killable process if it goes.
    private static let setLimit = dlsym(dlopen(nil, RTLD_NOW), "JSContextGroupSetExecutionTimeLimit")
        .map { unsafeBitCast($0, to: SetLimit.self) }

    static func apply(_ timeout: Duration, to context: JSContext) {
        setLimit?(JSContextGetGroup(context.jsGlobalContextRef), Double(timeout / .nanoseconds(1)) / 1e9, nil, nil)
    }
}
