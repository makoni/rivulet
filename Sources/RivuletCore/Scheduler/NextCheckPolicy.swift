// Ported from Miniflux internal/model/feed.go `ScheduleNextCheck` (Apache-2.0); adapted for
// Swift/SQLite.

import Foundation

/// The interval the refresh path schedules the next check on, and the instant it produces.
///
/// The reference reads the mode and the two interval pairs from `config.Opts` at commit
/// `c4d54f87`; here they are the values the policy is created with, and the defaults are the
/// reference's: the round-robin pair 60 and 1440 minutes, the entry-frequency pair 5 and 1440
/// with a factor of 1, and the mode `round_robin`. The order the reference applies them in is
/// the order this keeps: the mode's interval first, the delay the answer carries when it is
/// larger, and the maximum of the mode in effect as the cap on both.
///
/// The two modes read the weekly entry count differently, and that is what the pins show: the
/// entry-frequency mode divides the week by `weeklyCount × factor` and clamps the result, while the
/// round-robin mode takes the configured minimum and leaves the count alone, which is what the
/// reference does because it reads the count only for the entry-frequency mode. The count itself is
/// the storage rule `FeedRepository/weeklyEntryCount(_:feedID:now:)` answers; `weeklyCount` here is
/// the value that read produced.
///
/// The reference stamps `f.NextCheckAt = time.Now().Add(interval)`; here the instant is the
/// value the caller passes, so a test can pin the schedule against an injected clock.
public struct NextCheckPolicy: Sendable {
    /// The scheduler the reference's `PollingScheduler()` selects, as `options.go` validates it.
    public enum Mode: Sendable {
        /// The default, and the one that reads no weekly count.
        case roundRobin

        /// The mode that divides the week by the weekly count times the factor.
        case entryFrequency
    }

    /// The reference default for the round-robin minimum, in minutes.
    public static let defaultRoundRobinMinIntervalMinutes = 60

    /// The reference default for the round-robin maximum, in minutes.
    public static let defaultRoundRobinMaxIntervalMinutes = 1440

    /// The reference default for the entry-frequency maximum, in minutes.
    public static let defaultEntryFrequencyMaxIntervalMinutes = 1440

    /// The reference default for the entry-frequency minimum, in minutes.
    public static let defaultEntryFrequencyMinIntervalMinutes = 5

    /// The reference default for the entry-frequency factor.
    public static let defaultEntryFrequencyFactor = 1

    /// The mode the policy runs on.
    public let mode: Mode

    /// The round-robin minimum, in minutes.
    public let roundRobinMinIntervalMinutes: Int

    /// The round-robin maximum, in minutes; it caps any delay as well.
    public let roundRobinMaxIntervalMinutes: Int

    /// The entry-frequency minimum, in minutes.
    public let entryFrequencyMinIntervalMinutes: Int

    /// The entry-frequency maximum, in minutes; it caps any delay as well.
    public let entryFrequencyMaxIntervalMinutes: Int

    /// The entry-frequency factor, which multiplies the weekly count before the week is divided.
    public let entryFrequencyFactor: Int

    /// Creates a policy with the reference defaults, or with the values the configuration carries.
    public init(mode: Mode = .roundRobin,
        roundRobinMinIntervalMinutes: Int = Self.defaultRoundRobinMinIntervalMinutes,
        roundRobinMaxIntervalMinutes: Int = Self.defaultRoundRobinMaxIntervalMinutes,
        entryFrequencyMinIntervalMinutes: Int = Self.defaultEntryFrequencyMinIntervalMinutes,
        entryFrequencyMaxIntervalMinutes: Int = Self.defaultEntryFrequencyMaxIntervalMinutes,
        entryFrequencyFactor: Int = Self.defaultEntryFrequencyFactor) {
        self.mode = mode
        self.roundRobinMinIntervalMinutes = roundRobinMinIntervalMinutes
        self.roundRobinMaxIntervalMinutes = roundRobinMaxIntervalMinutes
        self.entryFrequencyMinIntervalMinutes = entryFrequencyMinIntervalMinutes
        self.entryFrequencyMaxIntervalMinutes = entryFrequencyMaxIntervalMinutes
        self.entryFrequencyFactor = entryFrequencyFactor
    }

    /// The instant the next check falls on, for the mode the policy was created with.
    /// - Parameters:
    ///   - now: The instant the schedule is built from, which is the injected clock's value.
    ///   - weeklyCount: The count the storage layer answered for the feed. A count of 0 or below
    ///     answers the entry-frequency maximum, because the division has no divisor; the reference
    ///     reads the count only for that mode, so the round-robin mode passes 0 and the
    /// number reads     nothing.   - refreshDelay: The delay the answer carries — `<ttl>`,
    /// `Retry-After`, `Cache-Control:     max-age` or `Expires` — as a `Duration`, which
    /// keeps its seconds. - Returns: The instant the next check falls on.
    public func nextCheckAt(now: Int, weeklyCount: Int, refreshDelay: Duration) -> Int {
        // The reference starts from the round-robin minimum and only the selected mode changes it.
        var interval = Duration.seconds(roundRobinMinIntervalMinutes * 60)

        if mode == .entryFrequency {
            if weeklyCount <= 0 {
                interval = Duration.seconds(entryFrequencyMaxIntervalMinutes * 60)
            } else {
                // Go's integer division truncates, so the week is divided as whole seconds.
                let seconds = 7 * 24 * 60 * 60 / (weeklyCount * entryFrequencyFactor)
                interval = Duration.seconds(seconds)
                interval = min(interval, Duration.seconds(entryFrequencyMaxIntervalMinutes * 60))
                interval = max(interval, Duration.seconds(entryFrequencyMinIntervalMinutes * 60))
            }
        }

        // Use the delay the answer carries when it is larger, then cap the interval with
        // the maximum of the mode in effect, which is the order the reference keeps.
        interval = max(interval, refreshDelay)
        switch mode {
        case .roundRobin:
            interval = min(interval, Duration.seconds(roundRobinMaxIntervalMinutes * 60))
        case .entryFrequency:
            interval = min(interval, Duration.seconds(entryFrequencyMaxIntervalMinutes * 60))
        }

        return now + Int(interval.components.seconds)
    }
}
