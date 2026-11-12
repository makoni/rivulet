/// RivuletCore — the core building blocks of Rivulet:
/// configuration, storage, feed fetching and the client-facing APIs.
public enum RivuletCore {
    /// Development version identifier. A client converts the version string to a number, so the
    /// digits it carries must read as a positive integer — the rule the pin for this value reads.
    public static let version = "0.1.0-dev"
}
