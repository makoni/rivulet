import Foundation
import NIOCore
import RivuletCore
import Vapor

/// The source the C handler answers. A C handler cannot capture an instance, so the process keeps
/// the one the wiring builds registered.
private nonisolated(unsafe) var binarySource: ServerSignalSource?

/// The handler the process runs when one of the two signals arrives: interrupt and SIGTERM, the two
/// the reference's daemon listens for (`internal/cli/daemon.go` at commit `c4d54f87`). It is put in
/// place before the server command runs, so a signal that arrives while the server is starting
/// answers the wait rather than ending the process on the default disposition. Once the command has
/// run it sets up its own handling for these signals, so from then on the arrival reaches the event
/// the command resolves; both paths answer the same wait, and both were observed on Linux.
///
/// The handler answers through the source, which means it takes a lock and resumes a continuation.
/// A signal handler is not async-signal-safe with a lock, so the shape keeps the guarded part
/// short: the handler runs once per arrival, and the wait it answers is the one that was open at
/// that arrival. The finding is recorded in `docs/plan/stage-6-cli.md`; it does not change what the
/// pins read.
private func handleSignal(_ signalNumber: Int32) {
    binarySource?.record(signalNumber)
}

/// The signal source the binary reads the stop decision through, with the two signals taken out of
/// the default disposition — which is what `signal.Notify` does in the reference, where the process
/// stops on the channel they feed rather than on the signal itself. Here the channel is the handler
/// above, joined with the event the server command resolves.
///
/// The first arrival is recorded once, so a signal that arrives during a decision and one that
/// arrives after it answer the same thing. A wait that is cancelled answers the cancellation it was
/// given, and only that wait: a later wait reads the arrival as a fact, never the previous wait's
/// cancellation, because the reference's channel read carries a value only when a signal is sent,
/// so nothing a decision left behind can answer the next one. No pin can read this rule: it bites
/// only in a loop, where a second wait opens after the first was cancelled, and the process pin
/// reads one decision. No in-process test reaches this type at all: `SystemCadenceTests` drives its
/// own seam, and `ServeProcessTests` reads the signal path as the event the child exits on.
public nonisolated final class ServerSignalSource: SignalSource, @unchecked Sendable {
    private let application: Application
    private let lock = NSLock()
    private var liveWaiter: Waiter?
    private var arrivedFlag = false
    private var eventJoined = false

    /// Builds the source around the application whose server command resolves the stop event, and
    /// puts the handler in place at once, before that command runs.
    /// - Parameter application: The application the server command runs on, whose event the wait
    /// joins.
    public init(_ application: Application) {
        self.application = application

        binarySource = self
        for signalNumber in [SIGINT, SIGTERM] {
            #if canImport(Glibc)
            Glibc.signal(signalNumber, handleSignal)
            #elseif canImport(Darwin)
            Darwin.signal(signalNumber, handleSignal)
            #endif
        }
    }

    /// Waits for the first stop signal and answers whether one arrived.
    ///
    /// It never answers before the signal arrives; when the waiting task is cancelled it answers
    /// `false`, which is the cancellation `SystemCadence` reads as "no signal by the decision". The
    /// event is the one the server command set up, so it is joined here on the first wait, after
    /// that command has run.
    /// - Returns: `true` when a signal arrived, `false` when this wait was cancelled by the
    /// decision.
    public nonisolated func signal() async -> Bool {
        joinEvent()
        let waiter = Waiter()

        return await withTaskCancellationHandler {
            let answered = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                lock.lock()
                waiter.continuation = continuation
                if arrivedFlag {
                    lock.unlock()
                    continuation.resume(returning: true)
                } else {
                    liveWaiter = waiter
                    lock.unlock()
                }
            }
            return answered
        } onCancel: {
            // This wait is the loser of the race the cadence runs, so it answers the cancellation
            // it was given rather than a signal that arrives later, and the answer goes only to
            // this wait.
            lock.lock()
            guard liveWaiter === waiter, let continuation = waiter.continuation else {
                lock.unlock()
                return
            }
            liveWaiter = nil
            waiter.continuation = nil
            lock.unlock()
            continuation.resume(returning: false)
        }
    }    /// Whether the first stop signal has already arrived.
    public nonisolated func arrived() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return arrivedFlag
    }

    /// Records the arrival and answers the wait that is open for it, from whichever path the signal
    /// reached the source: the handler above or the event the server command resolves. A source
    /// that has no wait open records the arrival as the fact the next decision reads.
    fileprivate nonisolated func record(_ signalNumber: Int32) {
        lock.lock()
        arrivedFlag = true
        let waiter = liveWaiter
        liveWaiter = nil
        lock.unlock()

        guard let waiter = waiter, let continuation = waiter.continuation else { return }
        waiter.continuation = nil
        continuation.resume(returning: true)
    }

    /// The event is joined once, so a caller that waits twice does not add the handler twice.
    private nonisolated func joinEvent() {
        lock.lock()
        if eventJoined {
            lock.unlock()
            return
        }
        eventJoined = true
        lock.unlock()

        if let onStop = application.running?.onStop {
            onStop.whenComplete { _ in
                self.record(0)
            }
        }
    }

    /// One wait, with the continuation it answers, so the cancellation is known to belong to this
    /// wait.
    private final class Waiter: @unchecked Sendable {
        var continuation: CheckedContinuation<Bool, Never>?
    }
}
