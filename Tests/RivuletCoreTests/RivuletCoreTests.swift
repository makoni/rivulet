import Testing
@testable import RivuletCore

@Suite struct RivuletCoreTests {
    @Test func versionIsPresent() {
        #expect(!RivuletCore.version.isEmpty)
    }
}
