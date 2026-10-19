import Foundation

/// Errors thrown while loading configuration from the environment.
public enum ConfigError: Error, Equatable, Sendable {
    /// A required environment variable is missing or empty.
    case missingRequiredVariable(String)

    /// An environment variable holds an unusable value.
    case invalidValue(variable: String, value: String, reason: String)
}

extension ConfigError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .missingRequiredVariable(let name):
            return "missing required environment variable: \(name)"
        case .invalidValue(let variable, let value, let reason):
            return "invalid value for \(variable): \"\(value)\" (\(reason))"
        }
    }
}
