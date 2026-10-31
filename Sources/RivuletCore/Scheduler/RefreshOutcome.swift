/// What one refresh of one feed produced, as the pipeline reports it.
///
/// The reference returns no value from `RefreshFeed`; this is what the port reports so a test can
/// read the outcome without reading the whole row back. `conditionalHit` is the answer the fetch
/// gave, the two hash lists follow the reference's storage branches — a new item is inserted, a
/// known item is refreshed when the refresh path updates existing entries — and `nextCheckAt` is
/// the schedule the pipeline stored for the feed.
public struct RefreshOutcome: Sendable, Equatable {
    /// The answer was a conditional hit, so nothing was parsed and no entry was written.
    public let conditionalHit: Bool

    /// Hashes of the entries this refresh inserted, in the order they were processed.
    public let newEntryHashes: [String]

    /// Hashes of the entries this refresh refreshed, in the order they were processed.
    public let updatedEntryHashes: [String]

    /// The instant the next check falls on, in Unix seconds, as stored for the feed.
    public let nextCheckAt: Int

    /// Creates the outcome.
    public init(conditionalHit: Bool, newEntryHashes: [String], updatedEntryHashes: [String],
        nextCheckAt: Int) {
        self.conditionalHit = conditionalHit
        self.newEntryHashes = newEntryHashes
        self.updatedEntryHashes = updatedEntryHashes
        self.nextCheckAt = nextCheckAt
    }
}
