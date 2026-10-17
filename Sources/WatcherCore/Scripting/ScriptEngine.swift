import Foundation
import JavaScriptCore

struct ScriptError: Error, CustomStringConvertible {
    let description: String
}

/// One JavaScript context for one script rule. All access happens on a private serial queue.
final class ScriptEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "watcher.script")
    private let context: JSContext
    private(set) var definesOnRequest = false
    private(set) var definesOnResponse = false

    // shortcut: no CPU timeout, so a script stuck in a synchronous infinite loop blocks its queue; upgrade by running scripts in a killable process.
    static let promiseTimeout: DispatchTimeInterval = .seconds(10)

    init(source: String, log: @escaping @Sendable (String) -> Void) {
        context = JSContext()!
        context.exceptionHandler = { _, exception in log("script error: \(exception?.toString() ?? "unknown")") }
        let console: @convention(block) (JSValue) -> Void = { log($0.toString() ?? "") }
        context.setObject(["log": console, "error": console, "warn": console, "info": console], forKeyedSubscript: "console" as NSString)
        // JavaScriptCore ships no atob/btoa; scripts and previewers need them for binary bodies.
        let atob: @convention(block) (String) -> String = { Data(base64Encoded: $0).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        let btoa: @convention(block) (String) -> String = { Data($0.utf8).base64EncodedString() }
        context.setObject(atob, forKeyedSubscript: "atob" as NSString)
        context.setObject(btoa, forKeyedSubscript: "btoa" as NSString)
        context.evaluateScript(source)
        definesOnRequest = context.evaluateScript("typeof onRequest === 'function'")?.toBool() ?? false
        definesOnResponse = context.evaluateScript("typeof onResponse === 'function'")?.toBool() ?? false
    }

    /// Calls a global function with JSON-encoded arguments and returns its (awaited) result as JSON.
    func call(_ function: String, argumentsJSON: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let once = Once(continuation)
            queue.async { [context] in
                let done: @convention(block) (JSValue?, JSValue?) -> Void = { result, error in
                    if let error, !error.isUndefined, !error.isNull {
                        once.resume(throwing: ScriptError(description: error.toString() ?? "script failed"))
                    } else {
                        once.resume(returning: result?.toString() ?? "null")
                    }
                }
                let invoke = context.evaluateScript("""
                (function (fn, args, done) {
                  try {
                    Promise.resolve(globalThis[fn](...JSON.parse(args)))
                      .then(function (r) { done(JSON.stringify(r === undefined ? null : r)); },
                            function (e) { done(null, String(e)); });
                  } catch (e) { done(null, String(e)); }
                })
                """)
                invoke?.call(withArguments: [function, argumentsJSON, unsafeBitCast(done, to: AnyObject.self)])
            }
            queue.asyncAfter(deadline: .now() + Self.promiseTimeout) {
                once.resume(throwing: ScriptError(description: "\(function) did not finish within 10 seconds"))
            }
        }
    }
}

/// Resumes a continuation at most once (a script can answer and time out).
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?

    init(_ continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: String) {
        take()?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        take()?.resume(throwing: error)
    }

    private func take() -> CheckedContinuation<String, Error>? {
        lock.withLock { defer { continuation = nil }; return continuation }
    }
}
