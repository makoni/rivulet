import Foundation
import Logging
import RivuletCore
import Synchronization

/// Process-wide swift-log bootstrap.
///
/// `LoggingSystem.bootstrap` may run only once per process: the first call wins and every
/// later call is ignored. Test support claims the same slot, so a command run in-process
/// can never bootstrap twice.
public enum LoggingSetup {
    private static let claimed = Mutex(false)

    /// Installs the process handler for the configured level and format.
    ///
    /// - `.text`: human-readable lines on standard error (`StreamLogHandler`).
    /// - `.json`: one JSON object per line (``JSONLogHandler``).
    ///
    /// Only the first call per process has an effect (see ``claimBootstrapSlot()``).
    public static func bootstrap(logLevel: Config.LogLevel, format: Config.LogFormat) {
        guard claimBootstrapSlot() else {
            return
        }
        let level = Logger.Level(logLevel)
        LoggingSystem.bootstrap { label in
            makeHandler(label: label, logLevel: level, format: format)
        }
    }

    /// Claims the one-time bootstrap slot; returns `false` when it is already taken.
    ///
    /// Internal because test support (`TestLogging`) installs a silent handler through it.
    static func claimBootstrapSlot() -> Bool {
        claimed.withLock { claimed in
            guard !claimed else {
                return false
            }
            claimed = true
            return true
        }
    }

    private static func makeHandler(
        label: String,
        logLevel: Logger.Level,
        format: Config.LogFormat
    ) -> any LogHandler {
        switch format {
        case .text:
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = logLevel
            return handler
        case .json:
            return JSONLogHandler(label: label, logLevel: logLevel) { line in
                FileHandle.standardError.write(Data(line.utf8))
            }
        }
    }
}

private extension Logger.Level {
    /// Maps the Miniflux-compatible ``Config/LogLevel`` onto swift-log.
    init(_ level: Config.LogLevel) {
        self = switch level {
        case .debug: .debug
        case .info: .info
        case .warning: .warning
        case .error: .error
        }
    }
}
