/// An error reported to the user by a Rivulet command.
public struct CLIError: Error, Equatable, Sendable, CustomStringConvertible {
    /// The user-facing message; the executable entry point prints it before exiting.
    public let message: String

    /// Creates an error from a user-facing message.
    public init(_ message: String) {
        self.message = message
    }

    /// See `CustomStringConvertible.description`.
    public var description: String { message }
}
