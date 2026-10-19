import Logging
@testable import RivuletApp

/// Bootstraps swift-log exactly once per test process.
///
/// All integration-test helpers must go through this instead of calling
/// `LoggingSystem.bootstrap` themselves: a second bootstrap call trips swift-log's
/// precondition. The single-process guard is shared with ``LoggingSetup``, so a command
/// run in-process cannot bootstrap again either.
enum TestLogging {
    private static let bootstrap: Void = {
        guard LoggingSetup.claimBootstrapSlot() else {
            return
        }
        LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }
    }()

    static func bootstrapOnce() {
        _ = bootstrap
    }
}
