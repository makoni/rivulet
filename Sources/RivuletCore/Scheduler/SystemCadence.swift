// Ported from Miniflux internal/cli/daemon.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The cadence the binary runs on: the interval the reference's ticker fires on, raced against the
/// stop signal, read as the decision the loop makes.
///
/// The reference's daemon selects on the stop channel and the ticker together
/// (`internal/cli/daemon.go` at commit `c4d54f87`): a firing with no signal reads the batch again,
/// and a signal answers the shutdown. This type is the port's shape of that select — the first path
/// to reach the decision answers it, and the decision ends the other one, so a signal arriving
/// after the decision does not answer it. Which path answers when both are ready at the same
/// instant is the choice no test can read; `SystemCadenceTests` names it, and the stop rule itself
/// is the port's own, recorded in `docs/parity.md`, because the reference's ticker goroutine has
/// none.
///
/// Each path answers the decision it was created for: a path that reaches the decision after that
/// decision was made has nothing to add, and it cannot answer a later one, because the answer a
/// path carries belongs to the wait that path was started from. No pin can read this rule: it bites
/// only when a path from one decision reaches the decision of the next, which needs two decisions
/// and a wait that answers, and a pin that waits is a timed wait. `SystemCadenceTests` names it in
/// its header.
///
/// Each path answers from the signal as it stands at the instant it answers. The signal path
/// answers on the answer it waited for, and the interval path answers on `arrived()`, which is the
/// signal as it stood when the interval fired: arrived, stop; not arrived, run again.
public nonisolated final class SystemCadence: Cadence, @unchecked Sendable {
    private let signalSource: any SignalSource
    private let lock = NSLock()
    private var pendingDecision: Decision?
    private var paths: [Task<Void, Never>] = []

    /// Builds the cadence around the signal it races the interval against.
    /// - Parameter signalSource: The seam the stop signal is read through. In the binary this is
    /// `ServerSignalSource`; a test drives its own so no pin waits for a signal.
    public init(signalSource: any SignalSource) {
        self.signalSource = signalSource
    }

    /// Makes one decision: wait for the interval, and answer whether the loop runs again.
    /// - Parameter interval: The cadence the loop hands to the seam, `pollingFrequency`.
    /// - Returns: `false` when the stop signal was read, `true` when it was not.
    public nonisolated func wait(for interval: Duration) async -> Bool {
        let decision = Decision()

        let again = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            decision.continuation = continuation
            pendingDecision = decision
            lock.unlock()

            paths = [Task { await self.answerFromSignal(decision) },
                     Task { await self.answerFromInterval(interval, decision) }]
        }

        paths.forEach { $0.cancel() }
        return again
    }

    private func answerFromSignal(_ decision: Decision) async {
        let answered = await signalSource.signal()
        answer(!answered, decision)
    }

    private func answerFromInterval(_ interval: Duration, _ decision: Decision) async {
        try? await Task.sleep(for: interval)
        answer(!signalSource.arrived(), decision)
    }

    /// Answers one decision, and only the decision the path was created for: a path that reaches
    /// here after its decision was made, or after a later one was opened, adds nothing.
    private func answer(_ again: Bool, _ decision: Decision) {
        lock.lock()
        defer { lock.unlock() }

        guard pendingDecision === decision, let continuation = decision.continuation else { return }
        pendingDecision = nil
        decision.continuation = nil
        continuation.resume(returning: again)
    }

    /// One decision, with the continuation that answers it and the identity a path is checked
    /// against.
    private final class Decision: @unchecked Sendable {
        var continuation: CheckedContinuation<Bool, Never>?
    }
}
