// Ported from Miniflux internal/cli/cleanup_tasks.go and
// internal/storage/entry.go (ArchiveEntries) (Apache-2.0); adapted for Swift/SQLite.
import Foundation

/// Retention policy, ported from the reference `CLEANUP_ARCHIVE_*` options.
public struct RetentionPolicy: Sendable, Equatable {
    /// Days after which entries with status `read` are archived.
    public var readEntryAgeDays: Int

    /// Days after which entries with status `unread` are archived.
    public var unreadEntryAgeDays: Int

    /// Maximum number of entries archived per status per run.
    public var batchSize: Int

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

/// Daily cleanup of archived entries (reference `runCleanupTasks`).
///
/// Archives all users' old entries in two passes — read first, then unread,
/// each in its own write transaction — mirroring the reference, which runs the
/// two `ArchiveEntries` calls back to back (retention is not scoped to one
/// user). Age is keyed on `created_at`, not `published_at`; starred entries
/// are always kept.
public struct Retention: Sendable {
    /// The ages and batch size applied by ``run(on:now:)``.
    public let policy: RetentionPolicy

    /// Creates a retention driver.
    /// - Parameter policy: Ages and batch size; the reference defaults apply
    ///   when omitted.
    public init(policy: RetentionPolicy = .default) {
        self.policy = policy
    }

    /// Runs the daily cleanup.
    ///
    /// A non-positive `batchSize` archives nothing (reference guard
    /// `limit <= 0`); a negative age skips that status (reference guard
    /// `interval < 0`); a zero age clamps to one day (reference
    /// `max(days, 1)`).
    ///
    /// - Parameters:
    ///   - on: The storage to clean.
    ///   - now: The current Unix seconds; the process clock applies when
    ///     omitted (tests pass a fixed value).
    /// - Returns: The number of archived entries per status.
    public func run(
        on storage: SQLiteStorage,
        now: Int = Int(Date.now.timeIntervalSince1970)
    ) async throws -> (read: Int, unread: Int) {
        var archived = (read: 0, unread: 0)
        guard policy.batchSize > 0 else {
            return archived
        }
        if policy.readEntryAgeDays >= 0 {
            archived.read = try await storage.withTransaction {
                try await EntryRepository($0).archive(
                    status: .read,
                    createdBefore: now - Self.ageSeconds(policy.readEntryAgeDays),
                    limit: policy.batchSize
                )
            }
        }
        if policy.unreadEntryAgeDays >= 0 {
            archived.unread = try await storage.withTransaction {
                try await EntryRepository($0).archive(
                    status: .unread,
                    createdBefore: now - Self.ageSeconds(policy.unreadEntryAgeDays),
                    limit: policy.batchSize
                )
            }
        }
        return archived
    }

    /// The reference truncates the interval to whole days and clamps to at
    /// least one day: `days := max(int(interval/(24*time.Hour)), 1)`.
    private static func ageSeconds(_ days: Int) -> Int {
        max(days, 1) * 86_400
    }
}
