import Foundation

/// The free-space check the `backup` run makes at its start.
///
/// The reference has no free-space check at all: its CLI dispatches by flags and has no backup
/// command, so this rule is the port's own, recorded in `docs/parity.md`. The estimate is the bytes
/// the source holds as the filesystem reads them, times the factor `docs/plan/stage-1-storage.md`
/// documents for `VACUUM INTO` (2), with the bytes the WAL holds counted, because the copy is built
/// from the rows the source has not checkpointed yet. The room is read at the directory the copy is
/// written to — the current directory for a destination named as a bare name, which is where such a
/// copy lands — and the comparison is read as strictly less, so a destination with exactly the
/// estimate holds the copy. A room the filesystem cannot read answers a refusal, because the run
/// cannot know whether the copy fits.
public struct FreeSpaceCheck: Sendable {
    /// The factor the estimate is built with, as `docs/plan/stage-1-storage.md` documents it.
    public static let factor: Int64 = 2

    private let space: any FileSystemSpace

    /// Builds the check around the filesystem it reads.
    /// - Parameter space: The filesystem the sizes and the room are read through, so a test
    /// answers the numbers it names instead of the numbers of the machine.
    public init(space: any FileSystemSpace) {
        self.space = space
    }

    /// The bytes the copy is expected to need.
    ///
    /// - Parameter sourcePath: The database file the run copies.
    /// - Returns: The bytes the main file and the `-wal` beside it hold, as read, times the
    /// factor. A size the filesystem cannot read counts as nothing, because a source that is not
    /// there has nothing to copy.
    public func estimate(sourcePath: String) -> Int64 {
        let main = space.size(of: sourcePath) ?? 0
        let wal = space.size(of: sourcePath + "-wal") ?? 0
        return (main + wal) * Self.factor
    }

    /// The refusal the run reports, or nothing when the room is enough.
    ///
    /// - Parameters:
    /// - sourcePath: The database file the run copies.
    /// - destinationPath: The path the copy is written to; the directory it names is the
    /// filesystem read.
    /// - Returns: The error the run reports, or `nil` when the copy fits.
    public func refusal(sourcePath: String, destinationPath: String) -> StorageError? {
        let needed = estimate(sourcePath: sourcePath)
        let directory = (destinationPath as NSString).deletingLastPathComponent
        let reported = directory.isEmpty ? "." : directory
        guard let room = space.freeSpace(at: reported) else {
            return StorageError.freeSpaceUnreadable(directory: reported)
        }
        return room < needed ? StorageError.notEnoughSpace(needed: needed, available: room) : nil
    }
}
