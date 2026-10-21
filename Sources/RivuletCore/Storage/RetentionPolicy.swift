// Ported from Miniflux internal/config defaults (CLEANUP_ARCHIVE_*) (Apache-2.0);
// adapted for Swift/SQLite.

/// Retention policy, ported from the reference `CLEANUP_ARCHIVE_*` options.
public struct RetentionPolicy: Sendable, Equatable {
    /// Days after which entries with status `read` are archived.
    public var readEntryAgeDays: Int

    /// Days after which entries with status `unread` are archived.
    public var unreadEntryAgeDays: Int

    /// Maximum number of entries archived per status per run.
    public var batchSize: Int

    /// Creates a policy.
    /// - Parameters:
    ///   - readEntryAgeDays: Age for `read` entries; a negative age skips that status.
    ///   - unreadEntryAgeDays: Age for `unread` entries; a negative age skips that status.
    ///   - batchSize: Entries per status per run; a non-positive batch archives nothing.
    public init(readEntryAgeDays: Int, unreadEntryAgeDays: Int, batchSize: Int) {
        self.readEntryAgeDays = readEntryAgeDays
        self.unreadEntryAgeDays = unreadEntryAgeDays
        self.batchSize = batchSize
    }

    /// Reference defaults: 60 days for read entries, 180 days for unread,
    /// batch of 10000.
    public static let `default` = RetentionPolicy(
        readEntryAgeDays: 60,
        unreadEntryAgeDays: 180,
        batchSize: 10_000
    )
}
