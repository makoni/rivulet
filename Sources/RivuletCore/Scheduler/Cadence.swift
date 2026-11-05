// Ported from Miniflux internal/cli/scheduler.go `feedScheduler` (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The seam the cadence loop waits through, so a test drives the cadence without sleeping.
///
/// The reference waits before it reads: `for range time.Tick(frequency)`
/// (`internal/cli/scheduler.go` at commit `c4d54f87`) fires only after the interval, so the first
/// batch read happens after the first interval and each later read after the next firing. The port
/// adds the answer, because its loop has to be able to stop: the reference's ticker goroutine has
/// no stop rule at all and runs until the process exits, so whether the loop runs again is the
/// port's own rule, recorded in `docs/parity.md`.
public protocol Cadence: Sendable {
    /// Waits for one interval and answers whether the loop runs again.
    ///
    /// - Parameter interval: The cadence the loop was built with, which is `pollingFrequency`. -
    /// Returns: Whether the loop should read the batch again.
    func wait(for interval: Duration) async -> Bool
}

