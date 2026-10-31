import Foundation

/// The process clock the application runs on: the current instant in Unix seconds.
///
/// The reference reads `time.Now()` inside its own functions; Rivulet keeps the clock as a seam
/// so the refresh path can be driven from an injected instant. This is the implementation the
/// application and the scheduler use; tests use a fixed clock instead.
public struct SystemClock: Clock {
    /// Creates the clock.
    public init() {}

    /// The current instant, in Unix seconds.
    public func now() -> Int {
        Int(Date.now.timeIntervalSince1970)
    }
}
