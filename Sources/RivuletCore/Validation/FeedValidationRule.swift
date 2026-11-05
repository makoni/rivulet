// Ported from Miniflux internal/validator/feed.go (Apache-2.0); adapted for Swift/SQLite.

/// The rule a feed the CLI adds fails on.
///
/// The first four cases are the reference's localized errors (`internal/validator/feed.go` at
/// commit `c4d54f87`), the ones the port keeps for the CLI path: the rules after them read the
/// filter and scraper settings a command line does not carry. The port names the rule rather than
/// the locale string, so the wording a command prints from it is its own; the reference's message
/// names are in `docs/reference-notes.md`.
///
/// The last three cases are the port's own, with no reference counterpart, because they name things
/// a command line has to answer and the reference's handler does not: which account a command is
/// working for, and a row the account has no row for. They are not part of the reference's rule
/// order, which `FeedValidationTests` pins, and their wording is the command's own.
public enum FeedValidationRule: String, CaseIterable, Sendable {
    /// `error.feed_mandatory_fields`: the url is required, and the category must be a positive id.
    case mandatoryFields

    /// `error.invalid_feed_url`: the input is not an absolute URL.
    case invalidURL

    /// `error.feed_already_exists`: the account already has a row with this url.
    case alreadyExists

    /// `error.feed_category_not_found`: the category the command resolved does not belong to the
    /// account, or does not exist.
    case categoryNotFound

    /// The port's own rule: no account is named and there is more than one to choose between.
    case multipleAccounts

    /// The port's own rule: the account named by the command has no row. The reference has no rule
    /// for this, because its request path reads the account before the rules run and reports a
    /// database failure rather than a rule.
    case accountNotFound

    /// The port's own rule: `remove` names a url this account has no row for.
    case feedNotFound
}
