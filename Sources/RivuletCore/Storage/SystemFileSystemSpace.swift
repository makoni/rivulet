import Foundation

#if canImport(Glibc)
import Glibc
#endif

/// The filesystem the application reads: the bytes a file holds, and the bytes the filesystem at a
/// directory has free for an unprivileged writer.
///
/// This is the implementation the commands run on; tests drive ``FileSystemSpace`` instead, because
/// the numbers of the machine this process runs on are not something a pin can name. A file that is
/// not there, or a directory whose metadata cannot be taken, answers nothing rather than
/// failing the run: the check reads a size it cannot read as nothing, because a source that is not
/// there has nothing to copy, and reads the room as not knowable, so it refuses before it writes.
public struct SystemFileSystemSpace: FileSystemSpace {
    /// Creates the filesystem the check reads.
    public init() {}

    /// The bytes `path` holds, or nothing when the filesystem cannot read it.
    public func size(of path: String) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        guard let size = attributes?[.size] as? NSNumber else { return nil }
        return Int64(size.int64Value)
    }

    /// The bytes the filesystem at `directory` has free for an unprivileged writer.
    ///
    /// `f_bavail` rather than `f_bfree`, because the reserved blocks of a filesystem are not room a
    /// writer can use, which is the number the run decides on.
    public func freeSpace(at directory: String) -> Int64? {
        #if canImport(Glibc)
        var info = statvfs()
        guard statvfs(directory, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_frsize)
        #elseif canImport(Darwin)
        var info = statfs()
        guard statfs(directory, &info) == 0 else { return nil }
        return Int64(info.f_bavail) * Int64(info.f_bsize)
        #else
        return nil
        #endif
    }
}
