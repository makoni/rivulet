import NIOCore
import Testing
@testable import RivuletCore

/// The fetcher's duration conversion. A deadline is a `TimeAmount` added to `NIODeadline.now()`, so a
/// duration read from the environment has to survive that arithmetic rather than trap.
@Suite struct FetcherTimingTests {
    @Test func anAbsurdDurationIsClampedRatherThanTrapping() {
        // `Duration.attoseconds` is Int128, and the conversion to `TimeAmount` would trap for a duration
        // larger than Int64 nanoseconds — about 292 years, which an environment value can reach. The
        // deadline arithmetic adds this to `NIODeadline.now()`, so the clamp leaves room for that too.
        #expect(Fetcher.amount(for: Duration.seconds(1_000_000_000_000_000_000))
            == TimeAmount.nanoseconds(Int64.max / 2))
    }

    @Test func anAbsurdNegativeDurationIsClampedRatherThanTrapping() {
        // `FetcherOptions` is public and takes any `Duration`, so a large negative one reaches the same
        // Int64 conversion. It clamps at the negative end, which stays a deadline in the past — the fetch
        // times out at once instead of trapping.
        #expect(Fetcher.amount(for: Duration.seconds(-1_000_000_000_000_000_000))
            == TimeAmount.nanoseconds(-(Int64.max / 2)))
    }
}
