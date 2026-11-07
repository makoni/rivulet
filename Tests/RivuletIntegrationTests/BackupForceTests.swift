import Foundation
import Testing
@testable import RivuletCore

/// `rivulet backup --force` as a run: what the flag lets the run replace, and what it does not
/// change.
///
/// The flag is the port's own: Miniflux's CLI dispatches by flags and has no `backup` command at
/// all, so there is nothing upstream to compare with. The rule is what the run does with a
/// destination that already holds something: without the flag it is refused and left as it was —
/// the rule `MaintenanceCommandTests` pin — and with the flag the file the destination names is
/// replaced by the snapshot the run writes, read as the filesystem reads the path rather than as a
/// database the run can open, while a path that is a directory is reported rather than deleted. The
/// flag does not change the room check, does not let a run that cannot write remove anything, and
/// does not build the directory the storage layer needs.
///
/// What these pins can fail on, each checked by patching the rule and reverting byte-identically,
/// with each probe named by what it flips — eight probes for five pins: the flag read as absent,
/// which refused the pins reading a replacement and the controls reading a run with room or a file
/// replaced; the destination read as a database the run can open, which refused the pin naming
/// bytes and the two controls reading bytes replaced; the room check skipped on the force path,
/// which wrote a copy over the bytes the no-room pin named; the destination removed before the
/// check, which left no bytes for that pin to read; the removal taking whatever the path is rather
/// than a file, which deleted the directory the pin that names a directory as the destination
/// built; the directory built on the force path, which answered the pin reading nothing created
/// with a copy; the write skipped on the force path, which left nothing for the copy reads that
/// show the controls writing; and the flag read as always on, which replaced the bytes the no-flag
/// control reads and is the only patch that can flip that control.
///
/// What these pins cannot fail on: an empty destination file, which the flag path replaces and the
/// no-flag path reuses, because both answers leave the same path with the same content, and reuse
/// is named as unpinnable by `MaintenanceCommandTests`; the type guard's other branches — a path
/// read as something other than a regular file, and one whose attributes cannot be read — which no
/// path this pin builds answers, and a symlink at the destination, which reads as the type its
/// target has, so the link itself is what the guard removes; the shape guard that reads the row the
/// pin wrote after the control run, which no patch of the command flips and which bites only on the
/// storage rules `MaintenanceTests` pins, as the same class is named there; the order the removal
/// of the destination and the migrations run in, which nothing in the run answers; the order
/// between the room check and the destination rule on the no-flag path, which no pin reads — what a
/// pin reads is that the check ran before anything was removed, written or read; the numbers a real
/// filesystem reports, which the seam answers in place of the machine, so the room it answers is
/// never read here; the size of the main file before the run, because the checkpoint at the end of
/// the run moves the rows from the WAL into it; the flag that gates the migrations, which
/// `MaintenanceCommandTests` pin for both commands; the copy being a plain file with no `-wal`
/// beside it; the wording of the lines and of the reported failures; that these commands fetch
/// nothing and sleep nothing; and the rules the port names rather than the reference, which has no
/// command here to compare with.
@Suite struct BackupForceTests {
    init() {
        TestLogging.bootstrapOnce()
    }

    // MARK: - Pins

    @Test func theForceFlagReplacesTheFileTheDestinationNamesAndNotAPathThatIsADirectory() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "not-a-file", content: "<p>Row for the run given a directory</p>")
                return try await content(on: connection)
            }

            // The guard reads the path as the filesystem reads it, so the run replaces a file and
            // nothing else: a patch that removed whatever the path was deleted the directory the
            // pin built, which is what a run has to report rather than delete.
            let directory = database.directory.appendingPathComponent("previous")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", directory.path])
            #expect(outcome.failed, "the run given a directory reports it: \(outcome.output)")
            #expect(FileManager.default.fileExists(atPath: directory.path),
                "the directory the pin built is left as it was: \(outcome.output)")

            // The control, on the same shape as a file: the run replaces it, so the readings above
            // are the type rule and not a command that writes nothing at a path it cannot write to.
            let file = database.directory.appendingPathComponent("previous-file")
            try "not a database".write(to: file, atomically: true, encoding: .utf8)
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", file.path])
            #expect(!control.failed, "the control run on the same shape as a file did not fail: \(control.output)")
            let replaced = try await content(at: file.path, on: database, as: "control")
            #expect(replaced == atTheRun, "the control run replaced the file: \(replaced)")
        }
    }

    @Test func theForceFlagReplacesADestinationTheRunWouldRefuseWithoutIt() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "force", content: "<p>Row for the run that replaced the destination</p>")
                return try await content(on: connection)
            }

            // The destination is bytes rather than a database, so what this pin reads is that the
            // flag applies to what the destination holds as the filesystem reads it, not as a
            // database the run can open: a patch that replaced only a destination openable as a
            // database refused this run and left the bytes where the pin reads them gone.
            let destination = database.directory.appendingPathComponent("previous.txt").path
            let bytes = "not a database"
            try bytes.write(to: URL(fileURLWithPath: destination), atomically: true, encoding: .utf8)

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", destination])
            #expect(!outcome.failed, "the run with the flag: \(outcome.output)")
            let replaced = try await content(at: destination, on: database, as: "replaced")
            #expect(replaced == atTheRun, "the destination is the snapshot the run wrote: \(replaced)")

            // The control: the same shape with the flag not given is refused and left as it was,
            // which is the rule `MaintenanceCommandTests` pin. Read as the control here, so a patch
            // that read the flag as always on failed this pin as well as the one above.
            let withoutFlag = database.directory.appendingPathComponent("without-flag.txt").path
            try bytes.write(to: URL(fileURLWithPath: withoutFlag), atomically: true, encoding: .utf8)
            let control = try await runCommand(databasePath: database.path, arguments: ["backup", withoutFlag])
            #expect(control.failed, "the same run without the flag: \(control.output)")
            #expect(try String(contentsOfFile: withoutFlag, encoding: .utf8) == bytes,
                "the destination the flag was not given is left as it was")
        }
    }

    @Test func theForceFlagReplacesThePreviousCopyWithTheSnapshotAtTheRun() async throws {
        try await withMigratedStorage { database, storage in
            let graph = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "first", content: "<p>Row the control run copied</p>")
                return (feed.userID, feed.feedID)
            }

            let previous = database.directory.appendingPathComponent("previous.db").path
            let control = try await runCommand(databasePath: database.path, arguments: ["backup", previous])
            #expect(!control.failed, "the control run did not fail: \(control.output)")

            // The write is not read by the line above, which reads only the run's answer; the copy
            // read here is what shows it, because a patch that skipped the write left no file for
            // this read to open.
            let first = try await content(at: previous, on: database, as: "first")

            // One row written after the control run: a run that replaces the destination carries
            // it, so this pin reads the replacement rather than the file the control run wrote. A
            // patch that read the flag as absent refused this run and answered the pin with
            // `first`, which is the same shape the no-flag refusal pin reads.
            let atTheRun = try await storage.withConnection { connection in
                _ = try await seedEntry(connection, userID: graph.0, feedID: graph.1,
                    hash: "after-the-control", content: "<p>Row the replacement carries</p>")
                return try await content(on: connection)
            }
            #expect(atTheRun.entries.count == first.entries.count + 1,
                "the row the pin wrote after the control run: \(atTheRun.entries)")

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", previous])
            #expect(!outcome.failed, "the run with the flag: \(outcome.output)")
            let replaced = try await content(at: previous, on: database, as: "again")
            #expect(replaced == atTheRun, "the destination is the snapshot the run wrote: \(replaced)")
            #expect(replaced != first, "the replacement is not the copy the control run left: \(replaced)")

            // The source is read at the path the environment names, not through the connection the
            // run had already opened, so a patch that moved the source to the destination — which
            // answers the same content — is shown by the file being gone rather than by a content
            // read.
            #expect(FileManager.default.fileExists(atPath: database.path),
                "the run that replaced the destination left the source: \(outcome.output)")
            let source = try await content(of: storage)
            #expect(source == atTheRun, "the source still holds its rows: \(source.entries)")
        }
    }

    @Test func theForceFlagDoesNotSkipTheRoomCheckAndLeavesTheDestinationAsItWas() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-room", content: "<p>Row for the run that had no room</p>")
                return try await content(on: connection)
            }

            // The numbers are the pin's, through the seam: less room than the estimate the rule
            // builds. The flag does not make a run that cannot write remove what the destination
            // holds, so the check is read before the replacement: a patch that skipped the check on
            // the force path removed the bytes and wrote a copy, and a patch that removed the
            // destination first left nothing here for the pin to read.
            let wal = database.path + "-wal"
            let space = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 7000)
            let destination = database.directory.appendingPathComponent("no-room.txt").path
            let bytes = "not a database"
            try bytes.write(to: URL(fileURLWithPath: destination), atomically: true, encoding: .utf8)

            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", destination], space: space)
            #expect(outcome.failed, "the run with the flag and less room than the estimate: \(outcome.output)")
            #expect(try String(contentsOfFile: destination, encoding: .utf8) == bytes,
                "the destination is left as it was when the run could not write")
            #expect(space.all() == [.size(database.path), .size(wal), .space(database.directory.path)],
                "the reads the run made before it refused: \(space.all())")

            // The control: the same shape with room answers a replaced destination, so the failure
            // above is the room rule and not a command that writes nothing. The room named here is
            // more than the estimate, so this control reads only that a run with room wrote, and a
            // patch that read the flag as always off failed it too.
            let room = RecordingSpace(sizes: [database.path: 4000, wal: 0], free: 9000)
            let written = database.directory.appendingPathComponent("room.txt").path
            try bytes.write(to: URL(fileURLWithPath: written), atomically: true, encoding: .utf8)
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", written], space: room)
            #expect(!control.failed, "the control run with room did not fail: \(control.output)")
            let copy = try await content(at: written, on: database, as: "control")
            #expect(copy == atTheRun, "the control run replaced what the destination held: \(copy)")
        }
    }

    @Test func theForceFlagDoesNotBuildTheDirectoryTheStorageLayerNeeds() async throws {
        try await withMigratedStorage { database, storage in
            let atTheRun = try await storage.withConnection { connection in
                let feed = try await seedFeed(connection)
                _ = try await seedEntry(connection, userID: feed.userID, feedID: feed.feedID,
                    hash: "no-parent", content: "<p>Row for the run with no parent directory</p>")
                return try await content(on: connection)
            }

            // The port does not build the directory the storage layer needs, with the flag or
            // without it: a patch that created it on the force path answered this pin with a copy.
            // The seam answers a room here, so what this pin reads is the destination rule, not the
            // room decision, and the order the two answer in is not something a pin can read.
            let missing = database.directory.appendingPathComponent("missing-dir/force.db").path
            let outcome = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", missing])
            #expect(outcome.failed,
                "the run reports it rather than answering as an empty run: \(outcome.output)")
            #expect(!FileManager.default.fileExists(atPath: missing), "no file was created")
            #expect(!FileManager.default.fileExists(
                atPath: (missing as NSString).deletingLastPathComponent), "no directory was created")

            // The control on the same shape as a file: with the directory the pin built, the run
            // with the flag answers it, and the copy read after the run is what shows the write, so
            // the readings above are the rule and not a command that writes nothing.
            let parent = database.directory.appendingPathComponent("built-dir")
            try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            let control = try await runCommand(databasePath: database.path,
                arguments: ["backup", "--force", parent.appendingPathComponent("force.db").path])
            #expect(!control.failed, "the control run on the same shape as a file did not fail: \(control.output)")
            let copy = try await content(at: parent.appendingPathComponent("force.db").path,
                on: database, as: "control")
            #expect(copy == atTheRun, "the control run wrote the copy: \(copy)")
        }
    }
}
