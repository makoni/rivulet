import Foundation
import Testing
@testable import RivuletCore

/// The filesystem the application reads, pinned for the two decisions a test can name without the
/// numbers of this machine: what a path the filesystem cannot read answers, and what a file the
/// test writes answers.
///
/// What these pins can fail on, each checked by patching the implementation and reverting: that a
/// path the filesystem cannot read answers nothing rather than a number, so a patch that answered 0
/// answered 0 here; and that a file answers the bytes it holds as the filesystem reports them, so a
/// patch that answered nothing, or counted the bytes another way, answered a different number here.
///
/// What these pins cannot fail on: the room, which is the machine's — `f_bavail` times `f_frsize`
/// is the number this filesystem has, and `f_bavail` rather than `f_bfree` is the choice of the
/// reserved blocks, which no test can name; the room for a directory whose metadata cannot be
/// taken, which the same pin cannot answer without the machine; the branch where the attributes
/// read succeeds and the file carries no size metadata, which no file the pin writes answers; the
/// `Darwin` branch, which Linux CI does not compile; and the numbers the check decides on, which
/// `FreeSpaceCheckTests` pins through the seam instead.
@Suite struct SystemFileSystemSpaceTests {
    @Test func aPathTheFilesystemCannotReadAnswersNothing() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }

        // Nothing is the answer for a path the filesystem cannot read, not 0: a patch that
        // answered 0 here — which is what the check reads as nothing for a size — answered 0 for
        // this pin. The name is in the pin's own directory and is not created, so nothing else has
        // to be absent.
        #expect(SystemFileSystemSpace().size(of: directory.path("not-there.sqlite")) == nil,
            "the answer for a path the filesystem cannot read")
    }

    @Test func aFileTheTestWritesAnswersTheBytesItHolds() async throws {
        let directory = try TemporaryDirectory()
        defer { directory.remove() }
        let path = directory.path("one-hundred-bytes.sqlite")
        try Data(repeating: 0, count: 100).write(to: URL(fileURLWithPath: path))

        // The bytes the test wrote are the number this pin names, so it does not read the machine:
        // a patch that answered nothing for a file it could read, or counted the bytes another way,
        // answered a different number here.
        #expect(SystemFileSystemSpace().size(of: path) == 100,
            "the bytes the filesystem reports for a file the test wrote")
    }
}
