import Foundation

/// The instant the refresh path stamps on.  The reference reads `time.Now()` inside its own
/// functions. The port keeps the clock as a seam, which is what `docs/plan/stage-4-ingestion.md`
/// asks for: a test drives the schedule and the stamps from an injected instant instead of
/// sleeping, so a pin can tell the clock it was given from the process one.
public protocol Clock: Sendable {
    /// The current instant, in Unix seconds, the unit the stored timestamps use.
    func now() -> Int
}
