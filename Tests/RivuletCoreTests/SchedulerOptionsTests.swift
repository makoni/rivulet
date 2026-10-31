import Foundation
import Testing
@testable import RivuletCore

/// The values the tick reads.  Every default is the reference's, from `internal/config/options.go`
/// at commit `c4d54f87`: `BATCH_SIZE` 100, `WORKER_POOL_SIZE` 16, `POLLING_PARSING_ERROR_LIMIT` 3,
/// `POLLING_LIMIT_PER_HOST` 0 and `POLLING_FREQUENCY` 60 minutes.  What these pins can fail on:
/// each number on its own.  What they cannot: the environment names, which stage 6 parses, and the
/// fact that the reference reads them through `config.Opts` while this port takes them as a value.
/// The rules that read a zero as a switch rather than as a number are pinned where they change the
/// query — in `SchedulerBatchTests` — because a switch is only observable through the query.
@Suite struct SchedulerOptionsTests {
    @Test func theDefaultsAreTheReferenceDefaults() {
        #expect(SchedulerOptions.defaults.batchSize == 100)
        #expect(SchedulerOptions.defaults.workerPoolSize == 16)
        #expect(SchedulerOptions.defaults.parsingErrorLimit == 3)
        #expect(SchedulerOptions.defaults.limitPerHost == 0)
        #expect(SchedulerOptions.defaults.pollingFrequency == .seconds(3600))
    }
}
