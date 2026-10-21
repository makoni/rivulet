/// A corpus of feeds and entries created by ``Seeding``.
public struct SeededCorpus: Sendable, Equatable {
    /// The id of the user that owns every seeded feed.
    public let userID: Int

    /// The number of feeds created.
    public let feeds: Int

    /// The number of entries created.
    public let entries: Int
}
