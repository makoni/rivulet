import Foundation
import Testing
@testable import RivuletCore

/// The free-space check the `backup` run makes at its start, read as the decision the rule answers.
///
/// The reference has no free-space check at all: its CLI has no backup command, so the rule is the
/// port's own, recorded in `docs/parity.md` — the estimate is the bytes the source holds as the
/// filesystem reads them, times the factor `docs/plan/stage-1-storage.md` documents for `VACUUM
/// INTO` (2), the room is read at the directory the copy is written to, and the comparison is read
/// as strictly less. The pins drive the filesystem through `Support/RecordingSpace.swift`, because
/// the numbers a real filesystem reports are the machine's and no pin can name them.
///
/// What these pins can fail on, each checked by patching the rule and reverting: that the estimate
/// is the size as read times the factor, so a patch that measured the copy as the size of the
/// source answered a smaller estimate; that the bytes the WAL holds count in the estimate, so a
/// patch that read only the main file answered a smaller estimate; that the estimate reads both the
/// main file and the `-wal` beside it, in that order, and that the room is read after the estimate,
/// so a patch that reordered the reads answered a different list; that the comparison is strictly
/// less, so a patch that read the boundary as less-or-equal answered a refusal at equality; that
/// the room is read at the directory the destination is in — the current directory for a
/// destination named as a bare name — so a patch that read the source's directory or kept the empty
/// name answered a different path; that a size the filesystem cannot read counts as nothing, so a
/// patch that treated an absent file as the room answered a refusal for an empty source; and that a
/// room the filesystem cannot read answers a refusal, so a patch that treated it as enough answered
/// nothing here.
///
/// What these pins cannot fail on: the numbers a real filesystem reports — the pins read the values
/// the seam answers, so the room `statvfs` answers on this machine is never read here; what the
/// system implementation answers for a path it cannot read and for a file the test writes is pinned
/// by `SystemFileSystemSpaceTests`, and what these pins read is the rule's use of those numbers;
/// which factor the copy would truly need, which is the documented choice of the port rather than a
/// fact about SQLite, read as the rule the pins name; that the check runs before the write or
/// before the migrations, which is the order the run's pins read through the calls they record, not
/// a rule of this type; the wording of the reported failure; the names the pins read the decision
/// by, which the test writes; and the rules the port names rather than the reference, which has
/// nothing here to compare with.
@Suite struct FreeSpaceCheckTests {
    @Test func theEstimateIsTheSizeAsReadTimesTheDocumentedFactor() async throws {
        let source = "/tmp/opencode/freespace/main.sqlite"
        let space = RecordingSpace(sizes: [source: 4000, source + "-wal": 0], free: 9000)
        let check = FreeSpaceCheck(space: space)

        // The factor is what the pin reads: a patch that measured the copy as the size of the
        // source answered 4000 here, which is the number this pin does not name.
        #expect(check.estimate(sourcePath: source) == 4000 * 2,
            "the estimate the rule answered for a source of 4000 bytes")
    }

    @Test func theBytesTheWALHoldsCountInTheEstimate() async throws {
        let source = "/tmp/opencode/freespace/wal.sqlite"
        // The rows a run has not checkpointed are still in the WAL, and the copy is built from
        // them, so a patch that estimated from the main file alone answered 4000 bytes, not 6000.
        let space = RecordingSpace(sizes: [source: 2000, source + "-wal": 1000], free: 7000)
        #expect(FreeSpaceCheck(space: space).estimate(sourcePath: source) == (2000 + 1000) * 2,
            "the estimate the rule answered for a source whose WAL holds bytes")
    }

    @Test func theEstimateReadsTheMainFileAndTheWALBesideItBeforeTheRoomIsRead() async throws {
        let source = "/tmp/opencode/freespace/paths.sqlite"
        let destination = "/tmp/opencode/freespace/out/copy.sqlite"
        let space = RecordingSpace(sizes: [source: 1000, source + "-wal": 1000], free: 9000)
        _ = FreeSpaceCheck(space: space).refusal(sourcePath: source, destinationPath: destination)

        // The paths and the order are what the pin reads: a patch that read only one of them, or
        // read the room before the estimate, answered a different list here.
        #expect(space.all() == [.size(source), .size(source + "-wal"), .space("/tmp/opencode/freespace/out")],
            "the reads the check made: \(space.all())")
    }

    @Test func lessThanTheEstimateRefusesAndEqualityDoesNot() async throws {
        let source = "/tmp/opencode/freespace/boundary.sqlite"
        let destination = "/tmp/opencode/freespace/out/copy.sqlite"

        // The boundary is read as strictly less: at equality the filesystem can hold the copy, so a
        // patch that compared with `<=` answered a refusal here.
        let equal = RecordingSpace(sizes: [source: 1000, source + "-wal": 0], free: 2000)
        #expect(FreeSpaceCheck(space: equal).refusal(sourcePath: source, destinationPath: destination) == nil,
            "the answer at the boundary")

        let less = RecordingSpace(sizes: [source: 1000, source + "-wal": 0], free: 1999)
        #expect(FreeSpaceCheck(space: less).refusal(sourcePath: source, destinationPath: destination)
            == StorageError.notEnoughSpace(needed: 2000, available: 1999),
            "the answer just below the boundary")
    }

    @Test func theRoomIsReadAtTheDirectoryTheDestinationIsIn() async throws {
        let source = "/tmp/opencode/freespace/data/main.sqlite"
        let destination = "/tmp/opencode/freespace/other/copy.sqlite"
        let space = RecordingSpace(sizes: [source: 1000, source + "-wal": 0], free: 9000)
        _ = FreeSpaceCheck(space: space).refusal(sourcePath: source, destinationPath: destination)

        // The copy is written at the destination, so the room that matters is the room at the
        // destination: a patch that read the source's directory answered
        // `/tmp/opencode/freespace/data`.
        #expect(space.all().last == .space("/tmp/opencode/freespace/other"),
            "the directory the check read: \(space.all())")
    }

    @Test func aDestinationNamedAsABareNameIsReadAtTheCurrentDirectory() async throws {
        let source = "/tmp/opencode/freespace/bare.sqlite"
        // The copy goes to the current directory, so that is the filesystem the room is read at: a
        // patch that kept the empty name the path gives answered an empty path here.
        let space = RecordingSpace(sizes: [source: 1000, source + "-wal": 0], free: 9000)
        _ = FreeSpaceCheck(space: space).refusal(sourcePath: source, destinationPath: "copy.sqlite")
        #expect(space.all().last == .space("."),
            "the directory the check read for a bare name: \(space.all())")
    }

    @Test func aSizeTheFilesystemCannotReadCountsAsNothing() async throws {
        let source = "/tmp/opencode/freespace/absent.sqlite"
        // A source the filesystem cannot read holds nothing, so nothing is needed. The room is
        // named as a positive number so the patch this pin reads can answer a refusal: one that
        // read the absent file as the room, or as part of the estimate, needed more than the room
        // it was given and refused here, which is what the pin reads must not happen.
        let space = RecordingSpace(sizes: [source: nil, source + "-wal": nil], free: 5000)
        #expect(FreeSpaceCheck(space: space).refusal(sourcePath: source,
            destinationPath: "/tmp/opencode/freespace/out/copy.sqlite") == nil,
            "the answer for a source the filesystem cannot read")
    }

    @Test func aRoomTheFilesystemCannotReadAnswersARefusal() async throws {
        let source = "/tmp/opencode/freespace/unreadable.sqlite"
        let directory = "/tmp/opencode/freespace/out"
        // The run cannot know whether the copy fits, so it does not write: a patch that read the
        // missing room as enough answered nothing here, and a patch that measured the copy as 0
        // bytes answered a different case.
        let space = RecordingSpace(sizes: [source: 1000, source + "-wal": 0], free: nil)
        #expect(FreeSpaceCheck(space: space).refusal(sourcePath: source, destinationPath: "\(directory)/copy.sqlite")
            == StorageError.freeSpaceUnreadable(directory: directory),
            "the answer for a room the filesystem cannot read")
    }
}
