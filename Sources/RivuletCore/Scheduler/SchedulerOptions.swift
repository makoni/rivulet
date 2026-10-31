// Ported from Miniflux internal/config/options.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The values the scheduler tick reads.
///
/// The defaults are the reference's, from `internal/config/options.go` at commit `c4d54f87`. The
/// reference reads them through `config.Opts`; this port takes them as a value so a test can drive
/// the tick with its own numbers. Three of them are read as switches rather than as numbers: the
/// builder appends the error condition only for a positive limit and the `LIMIT` clause only for a
/// positive batch size, and it applies the host filter only when the per-host limit is positive —
/// the per-host limit is not a SQL condition at all, it is applied while the rows are iterated.
/// Those readings are pinned in `SchedulerBatchTests`, where a switch changes the query or the
/// scan. `pollingFrequency` is the cadence the loop runs on; `tick()` does not read it, and the
/// loop lands with `rivulet serve`.
public struct SchedulerOptions: Sendable, Equatable {
    /// The cadence the loop runs on (`POLLING_FREQUENCY`): 60 minutes by the reference.
    public let pollingFrequency: Duration

    /// The batch size (`BATCH_SIZE`): 100 by the reference.
    public let batchSize: Int

    /// The worker pool size (`WORKER_POOL_SIZE`): 16 by the reference.
    public let workerPoolSize: Int

    /// The parsing-error limit (`POLLING_PARSING_ERROR_LIMIT`): 3 by the reference.
    public let parsingErrorLimit: Int

    /// The per-host limit (`POLLING_LIMIT_PER_HOST`): 0 — off — by the reference.
    public let limitPerHost: Int

    /// The reference defaults.
    public static let defaults = SchedulerOptions(pollingFrequency: .seconds(3600), batchSize: 100,
        workerPoolSize: 16, parsingErrorLimit: 3, limitPerHost: 0)

    /// Creates the options with the values the tick reads.
    public init(pollingFrequency: Duration, batchSize: Int, workerPoolSize: Int,
        parsingErrorLimit: Int, limitPerHost: Int) {
        self.pollingFrequency = pollingFrequency
        self.batchSize = batchSize
        self.workerPoolSize = workerPoolSize
        self.parsingErrorLimit = parsingErrorLimit
        self.limitPerHost = limitPerHost
    }
}