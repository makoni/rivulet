import Foundation
@testable import RivuletCore

/// The clock the pipeline tests read: it answers one instant, so every stamp a pin reads is the
/// injected value rather than the process clock, which the pins could not tell apart otherwise.
final class FixedClock: Clock, Sendable {
    private let instant: Int

    init(now: Int) {
        instant = now
    }

    func now() -> Int {
        instant
    }
}
