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
/// Each path answers the decision from the signal as it stands at the instant it answers. The
/// signal path answers on the answer it waited for, and the interval path answers on `arrived()`,
/// which is the signal as it stood when the interval fired: arrived, stop; not arrived, run again.
public nonisolated final class SystemCadence: Cadence, @unchecked Sendable {
    private let signalSource: any SignalSource
    private let lock = NSLock()
    private var pendingDecision: CheckedContinuation<Bool, Never>?
    private var paths: [Task<Void, Never>] = []

    /// Builds the cadence around the signal it races the interval against.
    ///
    /// - Parameter signalSource: The seam the stop signal is read through. In the binary this is
    ///   `ServerSignalSource`; a test drives its own so no pin waits for a signal.
    public init(signalSource: any SignalSource) {
        self.signalSource = signalSource
    }

    /// Makes one decision: wait for the interval, and answer whether the loop runs again.
    ///
    /// - Parameter interval: The cadence the loop hands to the seam, `pollingFrequency`.
    /// - Returns: `false` when the stop signal was read, `true` when it was not.
    public nonisolated func wait(for interval: Duration) async -> Bool {
        let again = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            lock.lock()
            pendingDecision = continuation
            lock.unlock()

            paths = [
                Task { await self.answerFromSignal() },
                Task { await self.answerFromInterval(interval) },
            ]
        }

        paths.forEach { $0.cancel() }
        return again
    }

    private func answerFromSignal() async {
        let answered = await signalSource.signal()
        answer(!answered)
    }

    private func answerFromInterval(_ interval: Duration) async {
        try? await Task.sleep(for: interval)
        answer(!signalSource.arrived())
    }

    /// Answers the decision once: the path that reaches it after the decision was made has nothing
    /// to add.
    private func answer(_ again: Bool) {
        lock.lock()
        defer { lock.unlock() }

        guard let continuation = pendingDecision else { return }
        pendingDecision = nil
        continuation.resume(returning: again)
    }
}
