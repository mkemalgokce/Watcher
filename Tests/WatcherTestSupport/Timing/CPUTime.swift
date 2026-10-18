import Darwin

/// CPU time the calling thread spends in `work`; unlike wall time it ignores how long the thread waited to be scheduled.
public func cpuTime(of work: () throws -> Void) rethrows -> Duration {
    let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
    try work()
    return .nanoseconds(Int64(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - start))
}
