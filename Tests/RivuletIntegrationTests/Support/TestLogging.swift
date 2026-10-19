import Logging

/// Bootstraps swift-log exactly once per test process.
///
/// All integration-test helpers must go through this instead of calling
/// `LoggingSystem.bootstrap` themselves: a second bootstrap call trips swift-log's
/// precondition.
enum TestLogging {
    private static let bootstrap: Void = {
        LoggingSystem.bootstrap { _ in SwiftLogNoOpLogHandler() }
    }()

    static func bootstrapOnce() {
        _ = bootstrap
    }
}
