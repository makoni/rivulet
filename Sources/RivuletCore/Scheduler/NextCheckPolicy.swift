// Ported from Miniflux internal/model/feed.go `ScheduleNextCheck` (Apache-2.0); adapted for
// Swift/SQLite.

/// The interval the refresh path schedules the next check on, and the instant it produces.
///
/// This is the round-robin policy: the interval is the configured minimum, a delay the answer
/// carries wins when it is larger, and the configured maximum caps both. The defaults are the
/// reference's from `internal/config/options.go` at the pinned commit. The entry-frequency mode is
/// not modelled here: it needs the weekly entry count, so it lands with the scheduler loop.
///
/// The reference stamps `f.NextCheckAt = time.Now().Add(interval)`; here the instant is the value
/// the caller passes, so a test can pin the schedule against an injected clock.
public struct NextCheckPolicy: Sendable {
    /// The reference default for the round-robin minimum, in minutes.
    public static let defaultMinIntervalMinutes = 60

    /// The reference default for the round-robin maximum, in minutes.
    public static let defaultMaxIntervalMinutes = 1440

    /// The configured minimum interval, in minutes.
    public let minIntervalMinutes: Int

    /// The configured maximum interval, in minutes; it caps any delay as well.
    public let maxIntervalMinutes: Int

    /// Creates a policy with the reference defaults or the configured pair.
    public init(minIntervalMinutes: Int = defaultMinIntervalMinutes,
        maxIntervalMinutes: Int = defaultMaxIntervalMinutes) {
        self.minIntervalMinutes = minIntervalMinutes
        self.maxIntervalMinutes = maxIntervalMinutes
    }

    /// The instant the next check falls on: `max(interval, delay)`, capped by the maximum, added to
    /// `now`. A delay below the minimum cannot shorten the interval; a delay above the maximum is
    /// capped.
    public func nextCheckAt(now: Int, refreshDelayMinutes: Int) -> Int {
        let interval = min(max(minIntervalMinutes, refreshDelayMinutes), maxIntervalMinutes)
        return now + interval * 60
    }
}
