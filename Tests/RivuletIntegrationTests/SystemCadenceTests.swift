import Testing
@testable import RivuletCore

/// The real implementation of the `Cadence` seam, read as the decisions it answers.
///
/// The reference's ticker goroutine has no stop rule at all; the seam's stop answer is the port's
/// own rule, recorded in `docs/parity.md`, so what pins can read here is only the decision: when a
/// stop signal is already present at the decision, the seam answers that the loop stops; when none
/// is present, it answers that the loop runs again. The pins name the interval as zero so nothing
/// waits, which keeps the decision observable without a timed wait.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the decision
/// answers stop when the signal is present at the decision, and that it answers keep-going when the
/// signal is not; that the signal the seam was given is the one it reads, not one it writes. The
/// pin that arms the seam reads the same answer from either path, so it does not depend on which
/// path answers first; the pin that does not arms can only be answered by the interval path,
/// because its seam has no signal to answer, and that is what the pin reads.
///
/// What these pins cannot fail on: that a real interval passes — every pin here names a zero
/// interval, so a patch that waits for a real interval cannot be read; that a signal arriving
/// during a real interval is answered before the interval ends, because in-process nothing answers
/// a sleeping wait, so the choice between the two paths when both are ready is not readable here,
/// and the process suite reads the real signal path as an event; that an answer belongs to the
/// decision the path was created for, which needs two decisions with one path still open, so no pin
/// can read it without a timed wait; the names the pins read the decisions by, which the test
/// writes; the shape of the seam itself, which is the port's choice; and the real signal source
/// behind the seam, which no in-process test can reach — the process suite pins the end-to-end
/// signal path as the event the child exits on.
@Suite struct SystemCadenceTests {
    @Test func signalPresentAtTheDecisionAnswersStop() async throws {
        let signal = TestSignal(armed: true)
        let cadence = SystemCadence(signalSource: signal)

        // The pin arms the signal before the decision, so the decision reads it without waiting. A
        // patch that ignored the seam's signal answered keep-going here.
        let again = await cadence.wait(for: .zero)
        #expect(!again, "the decision the armed seam answered: \(again)")
    }

    @Test func noSignalAtTheDecisionAnswersKeepGoing() async throws {
        let signal = TestSignal(armed: false)
        let cadence = SystemCadence(signalSource: signal)

        // The seam has no signal to read, so the decision is made without one, on the interval the
        // pin names as zero. A patch that always answered stop failed here, and on the pin above
        // the armed seam would have answered the same thing both ways.
        let again = await cadence.wait(for: .zero)
        #expect(again, "the decision the unarmed seam answered: \(again)")
    }

    /// The signal the seam reads: it answers when the pin armed it, and never answers when the pin
    /// did not, so the decision is the seam's and not the test's. The pin that arms the signal
    /// answers without waiting; the pin that does not arms never answers, so its decision is made
    /// on the interval the pin names as zero, and the seam only reaches the decision through
    /// `arrived()`.
    private final class TestSignal: SignalSource, @unchecked Sendable {
        private let armed: Bool

        init(armed: Bool) {
            self.armed = armed
        }

        func signal() async -> Bool {
            if armed { return true }

            // An unarmed seam has no signal to answer, so this wait never resolves on its own: the
            // decision can only be made by the interval path, and the wait is left cancelled.
            return await withTaskCancellationHandler {
                await withCheckedContinuation { (_: CheckedContinuation<Bool, Never>) in
                    // Resolving here would let the losing path answer the decision, which is what
                    // the race must not do, so the pin holds this wait open until it is cancelled.
                }
            } onCancel: {
                // Cancelled by the decision, which had already answered on the signal as it stood.
            }
        }

        func arrived() -> Bool {
            armed
        }
    }
}
