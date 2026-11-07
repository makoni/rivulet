import Foundation
import RivuletCore

/// The filesystem the pins drive instead of the one the process runs on.
///
/// The numbers a real filesystem reports are not something a pin can name: the room is the
/// machine's, so the seam answers the values the pin names and records the paths it was asked for.
/// What a pin reads is the rule the check applies to those values — the estimate, the boundary, and
/// which directory the room was read at — never the numbers of the machine this suite runs on.
final class RecordingSpace: FileSystemSpace, @unchecked Sendable {
    enum Call: Equatable {
        case size(String)
        case space(String)
    }

    private let lock = NSLock()
    private var calls: [Call] = []
    private let sizes: [String: Int64?]
    private let free: Int64?

    /// Builds the seam with the numbers the pin names: the bytes each path holds, `nil` for a path
    /// the filesystem cannot read, and the room the seam answers for any directory.
    init(sizes: [String: Int64?], free: Int64?) {
        self.sizes = sizes
        self.free = free
    }

    func size(of path: String) -> Int64? {
        record(.size(path))
        return sizes[path] ?? nil
    }

    func freeSpace(at directory: String) -> Int64? {
        record(.space(directory))
        return free
    }

    /// The paths the check read, in the order it read them.
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
