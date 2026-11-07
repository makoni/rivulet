import Foundation
import Testing
@testable import RivuletCore

/// `rivulet backup --verify` as a run: what the flag makes the run call, and what it does not
/// change. The flag is the port's own: Miniflux's CLI dispatches by flags and has no `backup`
/// command at all, so there is nothing upstream to compare with. The rule is what the run does with
/// the copy it wrote: the check reads the file at the path as the run read it, after the write,
/// through a connection of its own, and what it observed is what the run reports as the failure.
/// The copy is left as written, because the runbook restores another backup rather than repairing a
/// file the check named, so a run that reports a failing check does not remove the file it read.
/// What these pins read is the call the run makes through the `DatabaseVerifier` seam and the
/// failure the run reports for the answer the seam gives — the shape the room pins read, because
/// the problems a real file has are not something a pin can name. The storage rule `PRAGMA
/// quick_check` reads is pinned by `MaintenanceTests`, and the real implementation is pinned by
/// `SystemDatabaseVerifierTests`. What these pins can fail on, each checked by patching the rule
/// and reverting byte-identically, with each probe named by what it flips — nine probes for five
/// pins: the flag read as absent, which answered the pins reading a call as none and the controls
/// reading one call as none; the flag read as always on, which called the check for the run that
/// was not given it; the check called before the write as well, which answered the pins reading the
/// one call with two; the path read as the normalized one rather than as the run read it, which
/// answered the pin naming a `.` component with a different string; the answer read as nothing to
/// report, which let a run the seam answered with problems succeed; the copy removed when the
/// answer named problems, which left nothing for the read that shows the copy is left as written;
/// the room check skipped on the verify path, which let a run that could not hold the copy write
/// and call; the directory built on the verify path, which answered the pin reading nothing created
/// with a copy and a call; and the write skipped when the flag was given, which left nothing for
/// the copy reads that show the control runs wrote. What these pins cannot fail on: the problems of
/// a real file, which the seam answers in place of the machine and which
/// `SystemDatabaseVerifierTests` reads on a real one; the connection the check opens, which no
/// patch of this command can flip because the command has no other connection to read through; the
/// answer the check gives for a file whose check ran and observed no rows, which is the same answer
/// as the clean one through this seam and which `MaintenanceTests` pin as a storage rule; the
/// wording of the lines and of the reported failure; the order between the check and the
/// application's shutdown, which nothing in the run answers; the `-wal` and `-shm` files the
/// check's connection can leave beside the copy, which are the copy's own because WAL is a property
/// of the file it is; the size of the main file before the run, because the checkpoint at the end
/// of the run moves the rows from the WAL into it; the flag that gates the migrations, which
/// `MaintenanceCommandTests` pin for both commands; that these commands fetch nothing and sleep
/// nothing; and the rules the port names rather than the reference, which has no command here to
/// compare with.
@Suite struct BackupVerifyTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theVerifyFlagCallsTheCheckNothingForTheRunThatWasNotGivenIt() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "not-given", content: "<p>Row for the run that was not given the flag</p>")
                return try await content(on: connection)
            }

            // The control on the same shape reads the call, so the empty answer is the flag rule
            // and not a command that never calls the seam: a patch that read the flag as always off
            // failed the control, and a patch that read it as always on failed this pin.
            let notGiven = RecordingVerifier(problems: [])
            let plain = database.directory.appendingPathComponent("not-given.db").path
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", plain], verifier: notGiven)
            #expect(!outcome.failed, "the run without the flag: \(outcome.output)")
            #expect(notGiven.all().isEmpty, "the run that was not given the flag called the check nothing")

            let given = RecordingVerifier(problems: [])
            let checked = database.directory.appendingPathComponent("given.db").path
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", checked], verifier: given)
            #expect(!control.failed, "the control run with the flag did not fail: \(control.output)")
            #expect(given.all().count == 1, "the control run with the flag called the check once: \(given.all())")
            let copy = try await content(at: checked, on: database, as: "control")
            #expect(copy == atTheRun, "the control run wrote the copy: \(copy)")
        }
    }

    @Test func theVerifyFlagCallsTheCheckOnceForThePathTheRunReadItAndAfterTheWrite() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "after-the-write", content: "<p>Row the check read after the write</p>")
                return try await content(on: connection)
            }

            // The destination is named with the "." component, so the string this pin reads is the
            // path as the run read it: a patch that normalized it before the call answered this pin
            // with a different string. That the file was there at the call is the order the pin
            // reads — the check ran after the write, which a patch that checked before it could not
            // answer.
            let verifier = RecordingVerifier(problems: [])
            let destination = "\(database.directory.path)/./checked.db"
            #expect(!FileManager.default.fileExists(atPath: destination), "the copy is not there before the run")

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", destination], verifier: verifier)
            #expect(!outcome.failed, "the run: \(outcome.output)")
            #expect(verifier.all() == [RecordingVerifier.Call(path: destination, fileWasThere: true)],
                "the one call the run made, with the file there at the call: \(verifier.all())")

            // The call is not the write: the copy read here is what shows it, because a patch that
            // skipped the write left nothing for this read and nothing for the call to find.
            let copy = try await content(at: destination, on: database, as: "checked")
            #expect(copy == atTheRun, "the file the check read is the copy the run wrote: \(copy)")
        }
    }

    @Test func theRunReportsTheFailureTheCheckAnswersAndLeavesTheCopyAsWritten() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "reported", content: "<p>Row for the run that reported the check</p>")
                return try await content(on: connection)
            }

            // The problems are the seam's answer, not a file's damage: what this pin reads is the
            // failure the run reports for that answer, and that the copy is left as the run wrote
            // it — a run that reports does not remove the file the check read, which is what the
            // runbook restores. A patch that answered the problems as nothing to report left this
            // run passing, and a patch that removed the copy left nothing for the read below.
            let problems = ["page 2 root is wrong"]
            let verifier = RecordingVerifier(problems: problems)
            let destination = database.directory.appendingPathComponent("answered-problems.db").path
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", destination], verifier: verifier)
            #expect(outcome.failed, "the run the seam answered with problems: \(outcome.output)")
            #expect(verifier.all().count == 1,
                "the run that reported the failure still made the one call: \(verifier.all())")
            let copy = try await content(at: destination, on: database, as: "left")
            #expect(copy == atTheRun,
                "the copy the failing check read is still the snapshot the run wrote: \(copy)")

            // The control on the same shape: the same run with the seam answering clean does not
            // fail, so the failure above is the answer the seam gave and not a command that fails
            // at the check.
            let clean = RecordingVerifier(problems: [])
            let written = database.directory.appendingPathComponent("answered-clean.db").path
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", written], verifier: clean)
            #expect(!control.failed, "the control run the seam answered clean did not fail: \(control.output)")
            let controlCopy = try await content(at: written, on: database, as: "control")
            #expect(controlCopy == atTheRun, "the control run wrote the copy: \(controlCopy)")
        }
    }

    @Test func theVerifyFlagDoesNotChangeTheRoomCheckAndCallsNothingWhenTheRunCannotWrite() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-room", content: "<p>Row for the run that had no room</p>")
                return try await content(on: connection)
            }

            // The numbers are the pin's, through the seam: less room than the estimate the rule
            // builds. The flag does not make a run that cannot hold the copy call the check, so the
            // check is read as running after the room rule: a patch that skipped the room check on
            // the verify path wrote a copy here and called the seam, which is what this pin reads
            // as nothing.
            let wal = database.path + "-wal"
            let space = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 7000)
            let verifier = RecordingVerifier(problems: [])
            let destination = database.directory.appendingPathComponent("no-room.db").path
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", destination], space: space, verifier: verifier)
            #expect(outcome.failed, "the run with less room than the estimate: \(outcome.output)")
            #expect(space.all() == [.size(database.path), .size(wal), .space(database.directory.path)],
                "the reads the run made before it refused: \(space.all())")
            #expect(verifier.all().isEmpty, "the run that could not write called the check nothing: \(verifier.all())")
            #expect(!FileManager.default.fileExists(atPath: destination), "nothing was written")

            // The control with room answers a written copy and a call, so the readings above are
            // the room rule and not a command that writes nothing at any path.
            let room = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 9000)
            let controlVerifier = RecordingVerifier(problems: [])
            let written = database.directory.appendingPathComponent("room.db").path
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", written], space: room, verifier: controlVerifier)
            #expect(!control.failed, "the control run with room did not fail: \(control.output)")
            #expect(controlVerifier.all().count == 1,
                "the control run with room called the check once: \(controlVerifier.all())")
            let copy = try await content(at: written, on: database, as: "control")
            #expect(copy == atTheRun, "the control run wrote the copy: \(copy)")
        }
    }

    @Test func theVerifyFlagDoesNotBuildTheDirectoryTheStorageLayerNeeds() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-parent", content: "<p>Row for the run with no parent directory</p>")
                return try await content(on: connection)
            }

            // The port does not build the directory the storage layer needs, with the flag or
            // without it. The seam answers a room here, so what this pin reads is the destination
            // rule and not the room decision: the run reports it rather than building a path around
            // itself, and the check is not reached because nothing was written. A patch that built
            // the directory answered this pin with a copy and with a call.
            let space = RecordingSpace(sizes: [database.path: 4000, database.path + "-wal": 0], free: 9000)
            let verifier = RecordingVerifier(problems: [])
            let missing = database.directory.appendingPathComponent("missing-dir/verified.db").path
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", missing], space: space, verifier: verifier)
            #expect(outcome.failed,
                "the run reports it rather than answering as an empty run: \(outcome.output)")
            #expect(!FileManager.default.fileExists(atPath: missing), "no file was created")
            #expect(!FileManager.default.fileExists(
                atPath: (missing as NSString).deletingLastPathComponent), "no directory was created")
            #expect(verifier.all().isEmpty,
                "the run that wrote nothing called the check nothing: \(verifier.all())")

            // The control on the same shape as a file: with the directory the pin built, the run
            // with the flag answers it, and the copy read after the run is what shows the write.
            let parent = database.directory.appendingPathComponent("built-dir")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let controlVerifier = RecordingVerifier(problems: [])
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--verify", parent.appendingPathComponent("verified.db").path],
                space: space, verifier: controlVerifier)
            #expect(!control.failed, "the control run on the same shape as a file did not fail: \(control.output)")
            #expect(controlVerifier.all().count == 1,
                "the control run called the check once: \(controlVerifier.all())")
            let copy = try await content(at: parent.appendingPathComponent("verified.db").path,
                on: database, as: "control")
            #expect(copy == atTheRun, "the control run wrote the copy: \(copy)")
        }
    }
}
