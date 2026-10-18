/// Yields each time the user asks the command to stop, such as with Ctrl-C.
typealias ShutdownSignal = @Sendable () -> AsyncStream<Void>
