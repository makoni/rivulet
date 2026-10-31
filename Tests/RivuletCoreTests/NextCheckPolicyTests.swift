import Foundation
import Testing
@testable import RivuletCore

/// The interval the refresh path schedules the next check on: the policy or the delay the answer
/// carries, whichever is larger, capped by the policy maximum.  Every expected value is the
/// reference's, not this implementation's, so a failure here is a difference in the port and
/// `docs/parity.md` is the only way a difference can stay. Five of the cases are the round-robin
/// cases `internal/model/feed_test.go` asserts (`TestFeedScheduleNextCheckRoundRobinDefault`,
/// `...WithRefreshDelayAboveMinInterval`, `...BelowMinInterval`, `...AboveMaxInterval`,
/// `...RoundRobinMinInterval`), and six are the entry-frequency cases it asserts
/// (`TestFeedScheduleNextCheckEntryFrequencyMaxInterval`, `...MaxIntervalZeroWeeklyCount`,
/// `...MinInterval`, `...Factor`, `...SmallNewTTL`, `...LargeNewTTL`), all read at the reference
/// commit `c4d54f87` with `TZ=UTC`.  The reference asserts those against ranges around its own
/// `time.Now()`, so each case here states the exact instant the reference's rule produces against
/// the injected clock, which is the same rule.  What these cases can fail on: the cap, because a
/// delay above it pins the cap and a delay below it pins the max of the two; the default interval,
/// because a delay below it pins the interval while a delay above it pins the delay; the configured
/// minimum, because a delay below that pins the configured number rather than the default; the
/// precision, because a delay of a minute and a half past a one-minute minimum is added as the
/// reference adds it, which a comparison rounded to whole minutes drops; the mode, because the same
/// weekly count answers the round-robin minimum in one mode and the division in the other; and the
/// division, because it truncates as Go divides, which a rounding implementation drops.  What they
/// cannot fail on: the order of the two entry-frequency clamps, because for a pair the reference's
/// validator accepts they commute, and for the pair it would reject — a minimum above the maximum —
/// the mode's cap is applied again after the delay, so both orders answer the maximum; the
/// environment names, which stage 6 parses; the weekly count itself, which the storage layer
/// answers and is pinned by `WeeklyEntryCountTests`; and the part of a delay below a second,
/// because the clock answers Unix seconds, which is the unit the stored timestamps use.
@Suite struct NextCheckPolicyTests {
    /// The reference's defaults, from `internal/config/options.go` at `c4d54f87`.
    private let defaultPolicy = NextCheckPolicy()

    @Test func theDefaultIntervalIsTheReferenceDefault() {
        // `TestFeedScheduleNextCheckRoundRobinDefault`: no delay, so the policy interval answers.
        #expect(defaultPolicy.mode == .roundRobin)
        #expect(defaultPolicy.roundRobinMinIntervalMinutes == 60)
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0, refreshDelay: .zero)
            == 1_700_000_000 + 3600)
    }

    @Test func aDelayAboveTheDefaultIntervalWins() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayAboveMinInterval`.
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0,
            refreshDelay: .seconds(5400)) == 1_700_000_000 + 5400)
    }

    @Test func aDelayBelowTheDefaultIntervalDoesNotWin() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayBelowMinInterval`.
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0,
            refreshDelay: .seconds(1800)) == 1_700_000_000 + 3600)
    }

    @Test func aDelayAboveTheDefaultMaxIsCapped() {
        // `TestFeedScheduleNextCheckRoundRobinWithRefreshDelayAboveMaxInterval`, which the
        // reference reads as a cap on the interval, so a case that cannot cross the cap pins
        // nothing.
        #expect(defaultPolicy.roundRobinMaxIntervalMinutes == 1440)
        #expect(defaultPolicy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0,
            refreshDelay: .seconds(88200)) == 1_700_000_000 + 86400)
    }

    @Test func aConfiguredMinimumIsUsedWhenTheDelayIsBelowIt() {
        // `TestFeedScheduleNextCheckRoundRobinMinInterval`, read with the env value that test sets.
        let policy = NextCheckPolicy(roundRobinMinIntervalMinutes: 1,
            roundRobinMaxIntervalMinutes: 1440)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0, refreshDelay: .zero)
            == 1_700_000_000 + 60)
    }

    @Test func aDelayThatIsNotWholeMinutesAddsAsTheReferenceAddsIt() {
        // The reference adds a `time.Duration` to the clock without rounding, so a delay of a
        // minute and a half past the minimum schedules the half-minute as well. A comparison
        // rounded to whole minutes answers the minute and fails here.
        let policy = NextCheckPolicy(roundRobinMinIntervalMinutes: 1,
            roundRobinMaxIntervalMinutes: 1440)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0, refreshDelay: .seconds(90))
            == 1_700_000_000 + 90)
    }

    @Test func theEntryFrequencyDefaultsAreTheReferenceDefaults() {
        let policy = NextCheckPolicy(mode: .entryFrequency)
        #expect(policy.entryFrequencyFactor == 1)
        #expect(policy.entryFrequencyMaxIntervalMinutes == 1440)
        #expect(policy.entryFrequencyMinIntervalMinutes == 5)
    }

    @Test func theEntryFrequencyCapWinsForASmallWeeklyCount() {
        // `TestFeedScheduleNextCheckEntryFrequencyMaxInterval`: one entry a week apart is a week,
        // which the maximum caps, so the maximum answers.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyMinIntervalMinutes: 1,
            entryFrequencyMaxIntervalMinutes: 5)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 1, refreshDelay: .zero)
            == 1_700_000_000 + 300)
    }

    @Test func aZeroWeeklyCountAnswersTheEntryFrequencyMaximum() {
        // `TestFeedScheduleNextCheckEntryFrequencyMaxIntervalZeroWeeklyCount`, read with the env
        // values that test sets: the division has no divisor, so the reference takes the maximum
        // before any clamp. With the pair that test sets, the maximum is smaller than
        // the round-robin default, so a patch that falls back to the default cannot
        // cross it and this half of the case cannot fail; the second line, with the
        // reference defaults, is the half that can, so both are stated here.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyMinIntervalMinutes: 1,
            entryFrequencyMaxIntervalMinutes: 5)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 0, refreshDelay: .zero)
            == 1_700_000_000 + 300)
        #expect(NextCheckPolicy(mode: .entryFrequency).nextCheckAt(now: 1_700_000_000,
            weeklyCount: 0, refreshDelay: .zero) == 1_700_000_000 + 86400)
    }

    @Test func theEntryFrequencyFloorWinsForALargeWeeklyCount() {
        // `TestFeedScheduleNextCheckEntryFrequencyMinInterval`: 10080 entries a week is a minute,
        // which the floor lifts to the configured minimum.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyMinIntervalMinutes: 100,
            entryFrequencyMaxIntervalMinutes: 500)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 10080, refreshDelay: .zero)
            == 1_700_000_000 + 6000)
    }

    @Test func theFactorMultipliesTheWeeklyCount() {
        // `TestFeedScheduleNextCheckEntryFrequencyFactor`: the defaults with a count
        // of 7 divide the week to a day, and the factor of 2 halves it.
        // week to a day, and the factor of 2 halves it.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyFactor: 2)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 7, refreshDelay: .zero)
            == 1_700_000_000 + 43200)
    }

    @Test func aDelayBelowTheEntryFrequencyIntervalDoesNotWin() {
        // `TestFeedScheduleNextCheckEntryFrequencySmallNewTTL`: the floor put the interval at the
        // minimum, and the delay is half of it.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyMinIntervalMinutes: 100,
            entryFrequencyMaxIntervalMinutes: 500)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 10080,
            refreshDelay: .seconds(3000)) == 1_700_000_000 + 6000)
    }

    @Test func aDelayAboveTheEntryFrequencyIntervalWins() {
        // `TestFeedScheduleNextCheckEntryFrequencyLargeNewTTL`: the delay is twice the minimum and
        // below the maximum, so it answers.
        let policy = NextCheckPolicy(mode: .entryFrequency, entryFrequencyMinIntervalMinutes: 100,
            entryFrequencyMaxIntervalMinutes: 500)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 10080,
            refreshDelay: .seconds(12000)) == 1_700_000_000 + 12000)
    }

    @Test func aDelayAboveTheEntryFrequencyMaximumIsCappedByIt() {
        // The reference caps the interval with the maximum of the mode in effect, after the delay,
        // so a delay past the entry-frequency maximum cannot pass it. The round-robin pair is the
        // only place an earlier cap could come from, so the two pairs are set apart here: a
        // implementation that reads the interval pair for both modes answers 86400 and fails.
        let policy = NextCheckPolicy(mode: .entryFrequency, roundRobinMinIntervalMinutes: 60,
            roundRobinMaxIntervalMinutes: 1440, entryFrequencyMinIntervalMinutes: 1,
            entryFrequencyMaxIntervalMinutes: 5)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 1, refreshDelay: .seconds(600))
            == 1_700_000_000 + 300)
    }

    @Test func theRoundRobinModeIgnoresTheWeeklyCount() {
        // The same count that drives the division in the entry-frequency mode leaves the
        // round-robin interval where the minimum puts it. Without the mode test the division would
        // answer for both.
        let policy = NextCheckPolicy(mode: .roundRobin, entryFrequencyFactor: 1)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 10080, refreshDelay: .zero)
            == 1_700_000_000 + 3600)
    }

    @Test func theDivisionTruncatesAsGoDivides() {
        // 604800 seconds over a count of 11 is 54981.8, and Go's integer division answers 54981. An
        // implementation that rounds answers 54982 and fails here.
        let policy = NextCheckPolicy(mode: .entryFrequency)
        #expect(policy.nextCheckAt(now: 1_700_000_000, weeklyCount: 11, refreshDelay: .zero)
            == 1_700_000_000 + 54981)
    }

}
