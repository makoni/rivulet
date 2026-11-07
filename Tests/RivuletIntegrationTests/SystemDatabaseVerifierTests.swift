import Foundation
import Testing
@testable import RivuletCore

/// The check the run reads, on a real file: what the implementation answers for the file the path
/// names. `BackupVerifyTests` drives the seam because the problems a real file has are not
/// something a pin can name; this suite reads what the implementation answers for the files the
/// test builds, so the pins name a real copy written by the storage rule and the damage
/// `Support/DatabaseCorruption.swift` does to it. What the pins read is the answer for the file at
/// the path: the clean answer for a file the check read as clean, the problems for a file the pin
/// damaged, the file left as the bytes the storage rule wrote, and the failure reported for a path
/// the check cannot open — the same failure the startup check reports, so page damage and a path
/// that cannot be read are told apart in the runbook.
///
/// What these pins can fail on, each checked by patching the implementation and reverting byte-
/// identically, with each probe named by what it flips — six probes for four pins: the answer read
/// as problems for every file, which answered the pin naming a clean copy with problems and the pin
/// naming a damaged file with a problem that does not name the page it damaged; the answer read as
/// nothing for every file, which answered the pin naming a damaged file with nothing; the journal
/// mode set on the connection the check opened, which rewrote the header bytes the pin compared
/// after the check; the failure that prevented the check from running read as the clean answer
/// rather than as the failure reported, which answered the pin naming a path it cannot open as
/// clean; that same failure reported through a different storage failure, which answered the pin
/// reading the mapping as another error; and the path built by the check before it reads it, which
/// answered the pin reading nothing created with a directory it wrote.
///
/// What these pins cannot fail on: that the check opens a connection of its own, which no patch of
/// this implementation can flip because there is no other connection for it to read through — what
/// the pins read is the answer for the file at the path, and a connection on the source would have
/// answered the same thing for the same file; the branch where the check ran and observed no rows,
/// which no real file answers and which no pin reaches here, and which `MaintenanceTests` pin only
/// as what the check answers for a healthy file, a damaged page and a file that is not a database;
/// the detail read of the reported failure, which any non-empty wording satisfies; the header bytes
/// read before the check, which are the shape guard that bites only on the storage rules
/// `MaintenanceTests` pin; the connection being closed after the check, which nothing a pin reads
/// answers; the wording of the reported failure; the numbers of this machine, which the check reads
/// as the file has them; and the rules the port names rather than the reference, which has no
/// command here to compare with.
@Suite struct SystemDatabaseVerifierTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theCheckAnswersNothingForACleanCopy() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "clean-copy", content: "<p>Row the clean copy carries</p>")
            }
            let copy = database.directory.appendingPathComponent("clean-copy.db").path
            try await storage.backup(to: copy)

            // A real file, so the answer is what the check observed: a patch that read the answer
            // as problems for every file answered problems for this one.
            let problems = try await SystemDatabaseVerifier().problems(at: copy)
            #expect(problems.isEmpty, "what the check observed for the file it read as clean: \(problems)")
        }
    }

    @Test func theCheckAnswersTheProblemsTheRealCopyHas() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "damaged-copy", content: "<p>Row the damaged copy carries</p>")
            }
            let copy = database.directory.appendingPathComponent("damaged-copy.db").path
            try await storage.backup(to: copy)
            try DatabaseCorruption.page2CellCount(at: copy)

            // The damage is the file's, so the check has to see it: a patch that read the answer as
            // nothing for every file answered the clean answer here, and a patch that named a
            // problem without reading the file could not say which page the check saw.
            let problems = try await SystemDatabaseVerifier().problems(at: copy)
            #expect(!problems.isEmpty, "what the check observed for the file the pin damaged")
            #expect(problems.joined(separator: " ").contains("page 2"),
                "the check read the page the pin damaged: \(problems)")
        }
    }

    @Test func theCheckReadsTheCopyWithoutChangingTheFileItRead() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "plain-file", content: "<p>Row the copy carries</p>")
            }
            let copy = database.directory.appendingPathComponent("plain-file.db").path
            try await storage.backup(to: copy)

            // The journal mode is a property the file header carries — bytes 18 and 19 — and the
            // copy the storage rule writes answers 1 there, which is the mode a check does not
            // decide. A patch that enabled WAL on the connection the check opened rewrote those two
            // bytes, so a run that only reads the file it wrote would have changed the file the
            // runbook restores. The bytes read before the check are the shape guard: they bite only
            // on the storage rules, which `MaintenanceTests` pin.
            let before = try Data(contentsOf: URL(fileURLWithPath: copy))
            #expect([before[18], before[19]] == [1, 1],
                "the header the storage rule wrote: \([before[18], before[19]])")
            _ = try await SystemDatabaseVerifier().problems(at: copy)
            let after = try Data(contentsOf: URL(fileURLWithPath: copy))
            #expect(after == before, "the file the check read is left as the bytes it was written with")
        }
    }

    @Test func aPathTheCheckCannotOpenIsReportedRatherThanAnsweredAsClean() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        // The pin does not build the directory, so the check has to report what prevented it from
        // running: a patch that answered nothing when the file could not be opened — which is what
        // an open would answer for a file in a directory that is there — answered as clean here,
        // and a patch that built the path before reading it answered the pin reading nothing
        // created with a directory it wrote.
        let path = directory.path("missing-dir/not-there.sqlite")
        do {
            let problems = try await SystemDatabaseVerifier().problems(at: path)
            Issue.record("expected the check to report the path it cannot open, got: \(problems)")
        } catch {
            guard case StorageError.databaseCorrupt(let details) = error else {
                Issue.record("expected the failure the startup check reports, got: \(error)")
                return
            }
            #expect(!details.isEmpty, "what the check reported as the failure: \(details)")
        }

        // The check reads the file at the path; it is not the rule that builds the path, which the
        // `backup` run pins in `BackupVerifyTests`.
        #expect(!FileManager.default.fileExists(atPath: path), "no file was created")
        #expect(!FileManager.default.fileExists(
            atPath: (path as NSString).deletingLastPathComponent), "no directory was created")
    }
}
