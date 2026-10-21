import Testing
@testable import RivuletCore

/// The messages the CLI shows for storage failures.
@Suite struct StorageErrorTests {
    @Test func integrityMessageReportsWhatSQLiteSaw() {
        #expect(
            StorageError.databaseCorrupt(details: ["page 2 has 500 cells"]).description
                == "the startup integrity check failed: page 2 has 500 cells"
        )
        #expect(
            StorageError.databaseCorrupt(details: ["a", "b"]).description
                == "the startup integrity check failed: a | b"
        )
        // A failure that prevented the check is worded as a failed check, not as damage:
        // the detail is what SQLite reported, so a lock is not presented as page corruption.
        #expect(
            StorageError.databaseCorrupt(details: ["database is locked"]).description
                == "the startup integrity check failed: database is locked"
        )
    }

    @Test func otherMessagesStateTheCondition() {
        #expect(
            StorageError.checkpointBusy.description
                == "the WAL checkpoint is blocked by another connection; retry when it is idle"
        )
        #expect(
            StorageError.invalidSeeding(feeds: 0, entries: 5).description
                == "invalid corpus size: 0 feed(s), 5 entry/entries"
        )
    }
}
