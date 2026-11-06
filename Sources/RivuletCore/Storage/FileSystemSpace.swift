/// The filesystem the free-space check reads through.
///
/// The numbers a filesystem reports are the machine's, so the check reads them through this seam: a
/// test answers the values it names instead of the room the process runs on. `nil` is the answer
/// for what the filesystem cannot read — a file that is not there, or a directory whose metadata
/// cannot be taken — which the rule reads as nothing for a size and as not knowable for the room.
public protocol FileSystemSpace: Sendable {
    /// The bytes `path` holds, or nothing when the filesystem cannot read it.
    ///
    /// - Parameter path: The file the check measured.
    /// - Returns: The bytes the file holds, or `nil`.
    func size(of path: String) -> Int64?

    /// The bytes the filesystem at `directory` has free, or nothing when it cannot be read.
    ///
    /// - Parameter directory: The directory the copy would be written to.
    /// - Returns: The bytes free for an unprivileged writer, or `nil`.
    func freeSpace(at directory: String) -> Int64?
}
