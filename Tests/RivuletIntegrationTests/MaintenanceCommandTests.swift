import Foundation
import Testing
@testable import RivuletCore

/// `rivulet backup` and `rivulet vacuum` as runs through the in-process console over a temp
/// database: where the copy lands, what it holds, and what the run leaves on the filesystem.
///
/// The command surface is the port's own: Miniflux's CLI dispatches by flags and has no backup or
/// vacuum command, so these pins read what a run leaves behind — the file at the path, its content
/// read through a second driver, the size of the file — rather than the sentence it prints. The
/// storage rules the commands call are pinned as storage rules by `MaintenanceTests`, so what is
/// new here is the command's own choice of what it does with what the storage layer answers.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the copy is
/// written at the destination as the command read it; that the copy is the snapshot at the run and
/// not the main file at the run — the row the pin seeds last is in the WAL, and the copy is smaller
/// than the source that still holds the free pages; that the copy is a separate file which does not
/// change with the source after the run; that the run leaves the source as it was; that a
/// destination which already holds something is refused and left as it was, read against a row the
/// pin writes after the control run so an overwrite answers a different copy, and that a run which
/// wrote nothing reports it rather than answering as an empty run; that a destination without its
/// parent directory is reported with nothing created, because the command does not build the
/// directory the storage layer needs; that the vacuum run rebuilds the file the environment names
/// and releases the free pages the rows left behind; that it leaves the rows it rebuilds; and that
/// the migration flag gates both commands, read on a schema the command created rather than one the
/// test built; that the run refuses when the filesystem it reads has less room than the estimate
/// the rule builds, and writes nothing, which a patch that copied first and refused after fails;
/// that the boundary is read as strictly less, so the run at equality writes the copy; that the
/// check is the backup run's, which a patch that read the room for the vacuum run fails; that the
/// run reads the room through the seam it was given, which a patch that used the process filesystem
/// fails; and that the estimate the run reads is the bytes the seam answered for the main file and
/// for the `-wal` beside it.
///
/// What these pins cannot fail on: the truncating checkpoint `vacuum()` ends with, because
/// `RivuletApplication.shutdown()` runs a best-effort truncating checkpoint after every command, so
/// a patch that dropped the checkpoint from the run still left an empty WAL — that checkpoint is
/// pinned by `MaintenanceTests`; which file the environment names, which `ConfigTests` pin, so the
/// vacuum pin can fail only on the patch that does not run the vacuum at all; reusing an existing
/// empty destination file, which `MaintenanceTests` pin; that the copy is a plain file with no
/// `-wal` beside it, which no implementation of this command would write; the size of the main file
/// as it stands before the run, because the checkpoint at the end of the run moves the rows the pin
/// seeded from the WAL into it — the free-space pins read the sizes the seam answered, not the
/// bytes on disk; the numbers a real filesystem reports, which the seam answers in place of the
/// machine — the two decisions of the system implementation a test can name without the machine are
/// pinned by `SystemFileSystemSpaceTests`, and its room is never read here; that the check runs
/// before the migrations, which nothing in the run answers, so the pins read only that it ran
/// before the write, and the order between the check and the destination rules, which no pin reads;
/// the factor the copy would truly need, which is the documented choice of the port rather than a
/// fact about SQLite, read as the rule the pins name; the shape guards that read what the pin built
/// before the run — the WAL holding one row, the file bloated past the size the pin reads, the copy
/// being openable as a database — which bite only on the storage rules `MaintenanceTests` pins, not
/// on a patch of the command; the wording of the lines and of the reported failures; that these
/// commands fetch nothing and sleep nothing; and the rules the port names, not the reference, which
/// has no command here to compare with.
@Suite struct MaintenanceCommandTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theCopyLandsAtTheDestinationTheCommandReadIt() async throws {
        try await withMigratedStorage { database, storage in
            // The destination is a path outside the data directory, so a patch that read the
            // argument as a name inside that directory wrote the copy where this pin does not look.
            let outside = try TemporaryDirectory()
            defer { outside.remove() }
            let destination = outside.path("rivulet-2026-11-05.db")

            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", destination])
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(FileManager.default.fileExists(atPath: destination),
                "the copy is at the path the command was given: \(outcome.output)")
            #expect(outcome.output.contains(destination),
                "the run reports the path it wrote, as it was given: \(outcome.output)")
        }
    }

    @Test func theCopyIsTheSnapshotAtTheRunNotTheMainFileAtTheRun() async throws {
        try await withMigratedStorage { database, storage in
            // Free pages in the main file, so the copy the run writes is the compacted snapshot;
            // then one row the run has to carry which the main file does not hold, because the
            // write that put it there is still in the WAL. A patch that copied the file bytes
            // answered a copy without that row and with the size of the bloated source.
            let bloated = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<8 {
                    _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                        hash: "bloated-\(index)", content: String(repeating: "x", count: 250_000))
                }
                _ = try await EntryRepository(connection).archive(status: .unread,
                    createdBefore: Int(Date.now.timeIntervalSince1970) + 1, limit: 100)
                return (feed.userID, feed.feedID)
            }
            try await storage.checkpoint()

            let atTheRun = try await storage.withConnection { connection in
                _ = try await seedEntry(connection, userID: bloated.0, feedID: bloated.1,
                    hash: "in-the-wal", content: "<p>Not in the main file</p>")
                return try await content(on: connection)
            }
            #expect(atTheRun.entries.count == 1, "the row the pin left in the WAL: \(atTheRun.entries)")
            #expect(try fileSize(database.path + "-wal") > 0,
                "the row the pin reads is in the WAL, not in the main file")

            let destination = database.directory.appendingPathComponent("copy.db").path
            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", destination])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            let copy = try await content(at: destination, on: database, as: "copy")
            #expect(copy.entries == atTheRun.entries, "the copy is the content at the run: \(copy.entries)")
            #expect(copy.tables == atTheRun.tables, "the copy is openable as a database: \(copy.tables)")
            let copySize = try fileSize(destination)
            let sourceSize = try fileSize(database.path)
            #expect(copySize < sourceSize,
                "the copy is the compacted snapshot, not the file bytes: \(copySize) against \(sourceSize)")
        }
    }

    @Test func theCopyIsSeparateFromTheSourceAndDoesNotChangeWithItAfterTheRun() async throws {
        try await withMigratedStorage { database, storage in
            let before = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "at-the-run", content: "<p>Written before the run</p>")
                return (content: try await content(on: connection), userID: feed.userID,
                    feedID: feed.feedID)
            }

            let destination = database.directory.appendingPathComponent("copy.db").path
            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", destination])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            // A patch that made the copy the same file under another name — a link — answered this
            // pin with the row written after the run, because then the copy and the source are one.
            let after = try await storage.withConnection { connection in
                _ = try await seedEntry(connection, userID: before.userID, feedID: before.feedID,
                    hash: "after-the-run", content: "<p>Written after the run</p>")
                return try await content(on: connection)
            }
            #expect(after.entries.count == before.content.entries.count + 1,
                "the source has the row the copy must not carry: \(after.entries)")
            let copy = try await content(at: destination, on: database, as: "copy")
            #expect(copy == before.content,
                "the copy holds what the run wrote, not what came after it: \(copy)")
        }
    }

    @Test func theRunLeavesTheSourceAsItWas() async throws {
        try await withMigratedStorage { database, storage in
            let before = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "source", content: "<p>Source row</p>")
                return try await content(on: connection)
            }

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", database.directory.appendingPathComponent("copy.db").path])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            // A patch that moved the source to the destination answered the content read on the
            // connection it had already opened, so the pin also reads the file at the path the
            // environment names. The size of the main file is not what this pin reads, because the
            // checkpoint at the end of the run moves the rows the pin seeded from the WAL into it.
            #expect(FileManager.default.fileExists(atPath: database.path),
                "the source is still at the path the environment names: \(outcome.output)")
            let after = try await content(of: storage)
            #expect(after == before, "the run wrote nothing to the source: \(after.entries)")
            #expect(after.tables == before.tables, "the source is the same database: \(after.tables)")
        }
    }

    @Test func anExistingDestinationIsRefusedAndLeftAsItWas() async throws {
        try await withMigratedStorage { database, storage in
            let graph = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "refused", content: "<p>Row for the refused run</p>")
                return (feed.userID, feed.feedID)
            }

            // The refusal itself is the storage rule `MaintenanceTests` pin. What this pin reads is
            // the command's rule: a run that wrote nothing reports it, and the file it found is the
            // file it left. A patch that removed the existing destination first answered both cases
            // as success, and the same patch rewrote the copy from the source, which is why the pin
            // writes a row the copy must not carry.
            let previous = database.directory.appendingPathComponent("previous.db").path
            let control = try await runCommand(databasePath: database.path, arguments: ["backup", previous])
            #expect(!control.failed, "the control run writes the copy: \(control.output)")
            let first = try await content(at: previous, on: database, as: "first")

            // One row written after the control run: an overwrite answers this pin with a copy that
            // carries it, so the copy read after the refused run is read against what the control
            // run wrote, and the pin can tell a refusal from a rewrite.
            let source = try await storage.withConnection { connection in
                _ = try await seedEntry(connection, userID: graph.0, feedID: graph.1,
                    hash: "after-the-refusal", content: "<p>Row an overwrite would carry</p>")
                return try await content(on: connection)
            }
            #expect(source.entries.count == first.entries.count + 1,
                "the row the pin wrote after the control run: \(source.entries)")

            let second = try await runCommand(databasePath: database.path, arguments: ["backup", previous])
            #expect(second.failed, "a run that wrote nothing reports it: \(second.output)")
            let copy = try await content(at: previous, on: database, as: "again")
            #expect(copy == first, "the copy the control run wrote is left as it was: \(copy)")
            #expect(copy.entries != source.entries,
                "the copy is not the source rewritten by the refused run: \(copy.entries)")
            let text = database.directory.appendingPathComponent("text.db").path
            let bytes = "not a database"
            try bytes.write(to: URL(fileURLWithPath: text), atomically: true, encoding: .utf8)
            let third = try await runCommand(databasePath: database.path, arguments: ["backup", text])
            #expect(third.failed, "the run reports the refusal rather than an empty run: \(third.output)")
            #expect(try String(contentsOfFile: text, encoding: .utf8) == bytes,
                "the file that was already there is left as it was")
        }
    }

    @Test func aDestinationWithoutItsParentDirectoryIsReportedWithNothingCreated() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-parent", content: "<p>Row for the run with no parent directory</p>")
            }

            // The port does not build the directory the storage layer needs: a patch creating it
            // answered this pin with a copy, which is what the pin reads must not be there. The
            // seam answers a room here, so what this pin reads is the destination rule, not the
            // room decision; the order the two answer in is not something a pin can read.
            let missing = database.directory.appendingPathComponent("missing-dir/copy.db").path
            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", missing])
            #expect(outcome.failed,
                "the run reports it rather than answering as an empty run: \(outcome.output)")
            #expect(!FileManager.default.fileExists(atPath: missing), "no file was created")
            #expect(!FileManager.default.fileExists(
                atPath: (missing as NSString).deletingLastPathComponent), "no directory was created")

            // The control on the same file: with the directory the pin built, the run writes the
            // copy, so the readings above are the rule rather than a command that writes nothing.
            let parent = database.directory.appendingPathComponent("built-dir")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", parent.appendingPathComponent("copy.db").path])
            #expect(!control.failed, "the control run writes the copy: \(control.output)")
        }
    }

    @Test func theRunRefusesWhenTheFilesystemHasLessRoomThanTheEstimateAndWritesNothing() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-room", content: "<p>Row for the run that had no room</p>")
            }

            // The numbers are the pin's, through the seam: the main file as the seam reads it, the
            // WAL answered as holding nothing and still read by the rule, and less room than the
            // estimate the rule builds from them.
            let wal = database.path + "-wal"
            let space = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 7000)
            let destination = database.directory.appendingPathComponent("no-room.db").path
            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", destination],
                space: space)

            #expect(outcome.failed, "the run that had less room than the estimate: \(outcome.output)")
            // Nothing was written, which is what a patch that copied first and refused after would
            // answer with a copy here: the check is the run's start, not a rule read after the
            // write.
            #expect(!FileManager.default.fileExists(atPath: destination), "no copy was written")
            #expect(space.all() == [.size(database.path), .size(wal), .space(database.directory.path)],
                "the reads the run made before it refused: \(space.all())")

            // The control: the same run with room answers a copy, so the failure above is the rule
            // and not a command that writes nothing. The room named here is exactly the estimate,
            // so the control sits at the boundary too, and the `<=` patch flips it as well as the
            // next pin. What this pin reads on its own is that a run with room did not fail.
            let room = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 8000)
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", database.directory.appendingPathComponent("room.db").path],
                space: room)
            #expect(!control.failed, "the control run with room did not fail: \(control.output)")
        }
    }

    @Test func theRunWritesTheCopyAtTheBoundaryTheCheckReadsAsEqual() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "exact", content: "<p>Row for the run at the boundary</p>")
            }

            // Room exactly equal to the estimate: the boundary is read as strictly less, so a patch
            // that compared with `<=` refused here and left no copy.
            let space = RecordingSpace(sizes: [database.path: 1000, database.path + "-wal": 1000],
                free: 4000)
            let destination = database.directory.appendingPathComponent("exact.db").path
            let outcome = try await runCommand(databasePath: database.path, arguments: ["backup", destination],
                space: space)

            #expect(!outcome.failed, "the run at the boundary: \(outcome.output)")
            #expect(FileManager.default.fileExists(atPath: destination),
                "the copy the run at the boundary wrote: \(outcome.output)")
        }
    }

    @Test func theVacuumRunDoesNotAskForTheRoomTheBackupRunChecks() async throws {
        try await withMigratedStorage { database, storage in
            try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-check", content: "<p>Row for the vacuum run that checks nothing</p>")
            }

            // The check is the backup run's, not a rule every run makes: a patch that read the room
            // here answered a refusal on a seam named as having none. The pin reads that the run
            // did not fail and asked for nothing; the rebuild itself is read by another pin.
            let space = RecordingSpace(sizes: [database.path: 4000, database.path + "-wal": 0], free: 0)
            let outcome = try await runCommand(databasePath: database.path, arguments: ["vacuum"], space: space)
            #expect(!outcome.failed, "the vacuum run asked for nothing: \(outcome.output)")
            #expect(space.all().isEmpty, "the reads the vacuum run made: \(space.all())")
        }
    }

    @Test func theVacuumRunReleasesTheFreePagesTheRowsLeftBehind() async throws {
        try await withMigratedStorage { database, storage in
            let deleted = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<10 {
                    _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                        hash: "bloated-\(index)", content: String(repeating: "y", count: 300_000))
                }
                return try await EntryRepository(connection).archive(status: .unread,
                    createdBefore: Int(Date.now.timeIntervalSince1970) + 1, limit: 100)
            }
            #expect(deleted == 10, "the rows the pin deleted: \(deleted)")
            try await storage.checkpoint()
            let bloated = try fileSize(database.path)
            #expect(bloated > 3_000_000, "the file the pin bloated: \(bloated)")

            let outcome = try await runCommand(databasePath: database.path, arguments: ["vacuum"])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            // The rule this pin names is that the run rebuilds the file: a patch that reported the
            // size without rebuilding left the free pages where they were, and the pin reads the
            // shrink.
            let shrunk = try fileSize(database.path)
            #expect(shrunk < bloated / 2, "the run released the free pages: \(shrunk) against \(bloated)")
        }
    }

    @Test func theVacuumLeavesTheRowsItRebuilds() async throws {
        try await withMigratedStorage { database, storage in
            let before = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                for index in 0..<3 {
                    _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                        hash: "kept-\(index)", content: "<p>Row the rebuild must keep</p>")
                }
                return try await content(on: connection)
            }

            let outcome = try await runCommand(databasePath: database.path, arguments: ["vacuum"])
            #expect(!outcome.failed, "the run: \(outcome.output)")

            // A patch that deleted the rows before rebuilding answered this pin with an empty file.
            let after = try await content(of: storage)
            #expect(after == before, "the rebuild kept every row: \(after.entries)")
            #expect(after.entries.count == 3, "the rows the pin seeded: \(after.entries)")
        }
    }

    @Test func theMigrationFlagGatesTheseCommands() async throws {
        // The flag on: the schema is the one the command created, so the pin reads the tables the
        // run made rather than a schema the test built, and the copy carries them.
        let on = try TemporaryDirectory()
        defer { on.remove() }
        let onRun = try await runCommand(databasePath: on.path("on.db"), arguments: ["backup", on.path("copy.db")])
        #expect(!onRun.failed, "the run with the flag on: \(onRun.output)")
        #expect(try await tables(at: on.path("on.db")).contains("feeds"), "the flag on migrates")
        #expect(try await tables(at: on.path("copy.db")).contains("feeds"),
            "the copy carries the schema the command created")

        // The flag off: the command creates no schema, so what the pin reads is the absence, on
        // both the file the environment names and the copy the run wrote.
        let off = try TemporaryDirectory()
        defer { off.remove() }
        let offEnvironment = ["RUN_MIGRATIONS": "false"]
        let offBackup = try await runCommand(databasePath: off.path("off.db"),
            arguments: ["backup", off.path("copy.db")], environment: offEnvironment)
        #expect(!offBackup.failed, "the run with the flag off: \(offBackup.output)")
        let offTables = try await tables(at: off.path("off.db"))
        #expect(!offTables.contains("feeds"), "the flag off does not migrate: \(offTables)")
        let offCopyTables = try await tables(at: off.path("copy.db"))
        #expect(!offCopyTables.contains("feeds"),
            "the copy holds the schema the command did not create: \(offCopyTables)")

        let offVacuum = try await runCommand(databasePath: off.path("vacuum.db"),
            arguments: ["vacuum"], environment: offEnvironment)
        #expect(!offVacuum.failed, "the vacuum run with the flag off: \(offVacuum.output)")
        let vacuumTables = try await tables(at: off.path("vacuum.db"))
        #expect(!vacuumTables.contains("feeds"),
            "the flag off does not migrate for the vacuum run: \(vacuumTables)")
    }
}
