/// The database the copy check reads: the problems the integrity check observed at a path. The
/// check reads a file the run wrote, so the seam names the path it reads and answers what it
/// observed, and a test answers the problems it names instead of opening a real file — the damage a
/// real file has is not something a pin can name. An empty answer is what the check observed
/// nothing wrong, and what prevented the check from running leaves through the error path rather
/// than as an empty answer, because nothing observed is not the same as nothing wrong: that
/// distinction is the storage rule `SQLiteStorage.quickCheck()` pins.
public protocol DatabaseVerifier: Sendable {
    /// The problems the check observed at `path`, empty when it observed none.
    /// - Parameter path: The file the check read, as the run read it.
    /// - Returns: One line per problem the check observed.
    /// - Throws: What prevented the check from running, which is not a problem the file has.
    func problems(at path: String) async throws -> [String]
}
