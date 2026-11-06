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
private func handleSignal(_ signalNumber: Int32) {
    binarySource?.record(signalNumber)
}

/// The signal source the binary reads the stop decision through, with the two signals taken out of
/// the default disposition — which is what `signal.Notify` does in the reference, where the process
/// stops on the channel they feed rather than on the signal itself. Here the channel is the handler
/// above, joined with the event the server command resolves.
///
/// The first arrival is recorded once, so a signal that arrives during a decision and one that
/// arrives after it answer the same thing. No in-process test reaches this type:
/// `SystemCadenceTests` drives its own seam, and `ServeProcessTests` reads the signal path as the
/// event the child exits on.
public nonisolated final class ServerSignalSource: SignalSource, @unchecked Sendable {
    private let application: Application
    private let lock = NSLock()
    private var pending: CheckedContinuation<Bool, Never>?
    private var arrivedFlag = false
    private var cancelledFlag = false
    private var eventJoined = false

    /// Builds the source around the application whose server command resolves the stop event, and
    /// puts the handler in place at once, before that command runs.
    ///
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
    ///
    /// - Returns: `true` when a signal arrived, `false` when this wait was cancelled by the
    /// decision.
    public nonisolated func signal() async -> Bool {
        joinEvent()

        return await withTaskCancellationHandler {
            let answered = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                lock.lock()
                if arrivedFlag {
                    lock.unlock()
                    continuation.resume(returning: true)
                } else if cancelledFlag {
                    lock.unlock()
                    continuation.resume(returning: false)
                } else {
                    pending = continuation
                    lock.unlock()
                }
            }
            return answered
        } onCancel: {
            lock.lock()
            cancelledFlag = true
            if let waiter = pending {
                // This wait is the loser of the race the cadence runs, so it answers the
                // cancellation it was given rather than a signal that arrives later.
                pending = nil
                waiter.resume(returning: false)
            }
            lock.unlock()
        }
    }

    /// Whether the first stop signal has already arrived.
    public nonisolated func arrived() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return arrivedFlag
    }

    /// Records the arrival and answers the wait, from whichever path the signal reached the source:
    /// the handler above or the event the server command resolves.
    fileprivate nonisolated func record(_ signalNumber: Int32) {
        lock.lock()
        defer { lock.unlock() }
        arrivedFlag = true
        if let waiter = pending {
            pending = nil
            waiter.resume(returning: true)
        }
    }

    /// The event is joined once, so a caller that waits twice does not add the handler twice. A
    /// source that never waits does not change the process's signal handling beyond the handler its
    /// builder put in place.
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
}
