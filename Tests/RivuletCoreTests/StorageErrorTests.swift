import Foundation
import Testing
@testable import RivuletCore

/// The messages the CLI shows for storage failures, and the mapping the startup check uses.
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

    @Test func checkMappingKeepsCancellationAndMapsEverythingElse() {
        #expect(StorageError.integrityFailure(for: CancellationError()) is CancellationError)

        let mapped = StorageError.integrityFailure(for: CocoaError(.fileReadCorruptFile))
            as? StorageError
        #expect(
            mapped == StorageError.databaseCorrupt(
                details: [String(describing: CocoaError(.fileReadCorruptFile))]
            )
        )

        // A problem row is already a storage error; mapping it again must not rename it.
        let preserved = StorageError.integrityFailure(for: StorageError.checkpointBusy) as? StorageError
        #expect(preserved == StorageError.checkpointBusy)
    }
}
