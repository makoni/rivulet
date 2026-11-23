import Testing
@testable import RivuletApp
@testable import RivuletCore

/// The document this path writes for the account row, read as `internal/model/user.go` at
/// `c4d54f87` declares it.
///
/// What this pin can fail on, each shown by patching the rule and reverting it: the key set being
/// the three fields this port has columns for, which a patch that dropped one of them fires here;
/// the order the three are written in, which a patch that wrote `is_admin` before `username` fires
/// here; the hash not being written, which a patch that wrote the model's hash column fires here;
/// and the two value rules, a boolean written as `true` or `false` and a number written as a
/// number, which a patch that wrote either as a string fires here. Four patches reached this suite
/// and all four fired here alone in the round that showed these pins; the patch for the key order
/// also fires on the route suite's pins for the document as bytes and for the row the read
/// hands the handler, which is the round of the third slice.
///
/// What this pin cannot fail on: the reference's other fields, which this port's schema has no
/// column for. Its struct declares 32 fields and one of them is not written at all, so the answer
/// carries 31 there and three here; no pin can read a field the schema has no column for, so the
/// difference is recorded in `docs/parity.md`. The three values this pin reads are the ones it put
/// into the model itself, so what reaches them from a stored row is read by no pin here: the row
/// read and the handler that answers it are the slice that registers the route.
@Suite struct RestV1ShapeTests {
    @Test func theAccountDocumentCarriesTheKeySetTheSchemaHasColumnsFor() {
        let user = User()
        user.id = 7
        user.username = "alice"
        user.isAdmin = true
        user.passwordHash = "$2a$10$notwritten"

        #expect(RestV1Shape.userDocument(user).written() ==
            "{\"id\":7,\"username\":\"alice\",\"is_admin\":true}",
            "the three fields in the order the struct declares them, and the hash is left out")
    }
}
