import XCTest
@testable import RivuletCore

final class RivuletCoreTests: XCTestCase {
    func testVersionIsPresent() {
        XCTAssertFalse(RivuletCore.version.isEmpty)
    }
}
