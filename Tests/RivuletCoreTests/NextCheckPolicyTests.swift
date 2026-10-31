import Foundation
import Testing
@testable import RivuletCore

/// The interval the refresh path schedules the next check on: the policy or the delay the answer
/// carries, whichever is larger, capped by the policy maximum.  Every expected value is the
/// reference's, not this implementation's, so a failure here is a difference in the port and
/// `docs/parity.md` is the only way a difference can stay. Five of the cases are the round-robin
/// cases `internal/model/feed_test.go` asserts (`TestFeedScheduleNextCheckRoundRobinDefault`,
/// `...WithRefreshDelayAboveMinInterval`, `...BelowMinInterval`, `...AboveMaxInterval`,
/// `...RoundRobinMinInterval`), read at the reference commit `c4d54f87` with `TZ=UTC`. The sixth is
/// traced from the rule the reference applies: the corpus passes delays with a sub-minute part, but
/// it asserts ranges against its own `time.Now()`, so a sub-minute delay there can only trip the
/// lower bound of the range, and no exact instant can be ported from it. Here the clock is the
/// injected one, so each case pins the exact instant the reference's rule produces, which is the
/// same rule.  What these cases can fail on: the cap, because a delay above it pins the cap and a
/// delay below it pins the max of the two; the default interval, because a delay below it pins the
/// interval while a delay above it pins the delay; the configured minimum, because a delay below
/// that pins the configured number rather than the default; and the precision, because a delay of a
/// minute and a half past a one-minute minimum is added as the reference adds it, which a
/// comparison rounded to whole minutes drops.  What they cannot fail on: the entry-frequency mode,
/// which this slice does not read — it needs the weekly entry count, so it lands with the refresh
/// loop — the source of the interval, which is the pipeline's choice, pinned in
/// `RefreshPipelineTests`, and the part of a delay below a second, because the clock answers Unix
/// seconds, which is the unit the stored timestamps use.
@Suite struct NextCheckPolicyTests {
    /// The reference's defaults, from `internal/config/options.go` at `c4d54f87`.
    private let defaultPolicy = NextCheckPolicy()

    @Test func theDefaultIntervalIsTheReferenceDefault() {
        // `TestFeedScheduleNextCheckRoundRobinDefault`: no delay, so the policy interval answers.
        #expect(defaultPolicy.minIntervalMinutes == 60)
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, refreshDelay: .zero)
            == 1_700_000_000 + 3600)
    }

    @Test func aDelayAboveTheDefaultIntervalWins() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayAboveMinInterval`.
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, refreshDelay: .seconds(5400))
            == 1_700_000_000 + 5400)
    }

    @Test func aDelayBelowTheDefaultIntervalDoesNotWin() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayBelowMinInterval`.
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, refreshDelay: .seconds(1800))
            == 1_700_000_000 + 3600)
    }

    @Test func aDelayAboveTheDefaultMaxIsCapped() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayAboveMaxInterval`, which the
        // reference reads as a cap on the interval, so a case that cannot cross the cap pins
        // nothing.
        #expect(defaultPolicy.maxIntervalMinutes == 1440)
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, refreshDelay: .seconds(88200))
            == 1_700_000_000 + 86400)
    }

    @Test func aConfiguredMinimumIsUsedWhenTheDelayIsBelowIt() {
        // `TestFeedScheduleNextCheckRoundRobinMinInterval`, read with the env value that test sets.
        let policy = NextCheckPolicy(minIntervalMinutes: 1, maxIntervalMinutes: 1440)
        #expect(policy.nextCheckAt(now: 1_700_000_000, refreshDelay: .zero)
            == 1_700_000_000 + 60)
    }

    @Test func aDelayThatIsNotWholeMinutesAddsAsTheReferenceAddsIt() {
        // The reference adds a `time.Duration` to the clock without rounding, so a delay of a
        // minute and a half past the minimum schedules the half-minute as well. A comparison
        // rounded to whole minutes answers the minute and fails here.
        let policy = NextCheckPolicy(minIntervalMinutes: 1, maxIntervalMinutes: 1440)
        #expect(policy.nextCheckAt(now: 1_700_000_000, refreshDelay: .seconds(90))
            == 1_700_000_000 + 90)
    }
}
