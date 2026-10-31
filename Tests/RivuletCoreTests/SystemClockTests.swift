import Foundation
import Testing
@testable import RivuletCore

/// The production clock must answer Unix seconds, the unit the stored timestamps use, as the
/// reference's `time.Now()` reads. The injected seam is what lets the pipeline pins read an instant
/// the process clock could not produce, so the two sides of the seam are pinned separately: the
/// pipeline suite pins the injected instant, and this pins that the production side answers the
/// same unit. The expected value here is a range against `Date.now` because a clock reports the
/// current instant; it can fail if the implementation switches unit, for example to milliseconds.
@Suite struct SystemClockTests {
    @Test func systemClockAnswersUnixSecondsOfTheProcessClock() {
        let before = Int(Date.now.timeIntervalSince1970)
        let value = SystemClock().now()
        #expect(before <= value && value <= Int(Date.now.timeIntervalSince1970))
    }
}
