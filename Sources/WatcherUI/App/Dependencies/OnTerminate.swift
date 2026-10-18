/// Registers work to run when the app quits.
public typealias OnTerminate = @MainActor (@escaping @MainActor () -> Void) -> Void
