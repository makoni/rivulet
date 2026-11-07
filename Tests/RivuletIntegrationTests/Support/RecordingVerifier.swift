import Foundation
import RivuletCore

/// The check the pins drive instead of a connection: it answers the problems the pin names and
/// records the calls the run made through it. The problems a real file has are not something a pin
/// can name, so the seam answers what the pin names and records the path it was asked for. What a
/// pin reads is the rule the run applies to that answer — that it called at all, the path it called
/// for, and the failure the run reports — never the damage of a file this suite cannot build; the
/// real implementation is pinned by `SystemDatabaseVerifierTests`. The helper also records whether
/// the file was already there when the call happened. That is a read the helper makes on the
/// filesystem itself, not a rule the check applies, and it is how a pin reads the check as running
/// after the write rather than before it: a patch that checked first answered a pin that names the
/// file as there at the call with it not there.
final class RecordingVerifier: DatabaseVerifier, @unchecked Sendable {
    /// One call: the path the run called for, and whether the file was there at the call.
    struct Call: Equatable {
        let path: String
        let fileWasThere: Bool
    }

    private let lock = NSLock()
    private var calls: [Call] = []
    private let problems: [String]

    /// Builds the seam with the answer the pin names: the problems the check reports for the path.
    init(problems: [String]) {
        self.problems = problems
    }

    func problems(at path: String) async throws -> [String] {
        let call = Call(path: path, fileWasThere: FileManager.default.fileExists(atPath: path))
        record(call)
        return problems
    }

    /// The calls the run made, in the order it made them.
    func all() -> [Call] {
        lock.lock()
        defer { lock.unlock() }
        return calls
    }

    private func record(_ call: Call) {
        lock.lock()
        calls.append(call)
        lock.unlock()
    }
}
