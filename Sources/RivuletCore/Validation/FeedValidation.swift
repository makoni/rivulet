// Ported from Miniflux internal/validator/feed.go (Apache-2.0); adapted for Swift/SQLite.

import Foundation

/// The rules a feed the CLI adds fails on.
///
/// The order is the reference's: `ValidateFeedCreation` applies the mandatory guard, then the
/// absolute-URL rule, then the duplicate read, then the category read, and `FeedValidationTests`
/// pins that order on the inputs that fail two rules at once. The rules after the fourth read the
/// filter, scraper and proxy settings a command line does not carry, so they are not ported here.
///
/// The three reads the rules consult are handed in as values, because the storage layer and the URL
/// rules answer them: a rule that read the database could not be pinned as a rule, so
/// `FeedManagementReadsTests` pins the duplicate read and the category read, `URLRulesTests` pin
/// the absolute-URL rule, and `FeedCommandTests` pins the command that applies the order. The
/// reference applies the last two rules the other way round on its discovery path, which is a
/// different function and is recorded in `docs/reference-notes.md`.
public enum FeedValidation {
    /// Applies the modification rules in the reference's order and names the first one the input fails
    /// on, or `nil` when it fails none.
    ///
    /// A rule is reached only for a field the request carried, because the modification shape declares
    /// pointers: a field the request did not carry is nothing, not an empty string, so the empty check
    /// cannot fire for it. The order is the reference's: the feed url block, the site url block, the
    /// title, the category read. `RestV1FeedRouteTests` pins the first two rules against the duplicate
    /// read on an input that fails both.
    ///
    /// - Parameters:
    ///   - feedURL: The url the request carried, or nothing.
    ///   - siteURL: The site url the request carried, or nothing.
    ///   - title: The title the request carried, or nothing.
    ///   - categoryID: The category the request carried, or nothing.
    ///   - feedURLIsAbsolute: The answer the URL rules give for the url the request carried.
    ///   - siteURLIsAbsolute: The answer the URL rules give for the site url the request carried.
    ///   - anotherFeedURLExists: The duplicate answer for this account and this url, read for the pair
    ///     with the row being modified excluded.
    ///   - categoryExists: The answer for whether this account has the category the request carried.
    /// - Returns: The first rule the input fails on, or `nil`.
    public static func validateModification(feedURL: String?, siteURL: String?, title: String?,
        categoryID: Int?, feedURLIsAbsolute: Bool, siteURLIsAbsolute: Bool,
        anotherFeedURLExists: Bool, categoryExists: Bool) -> FeedValidationRule? {
        if let feedURL {
            if feedURL.isEmpty { return .feedURLNotEmpty }
            if !feedURLIsAbsolute { return .invalidURL }
            if anotherFeedURLExists { return .alreadyExists }
        }
        if let siteURL {
            if siteURL.isEmpty { return .siteURLNotEmpty }
            if !siteURLIsAbsolute { return .invalidSiteURL }
        }
        if let title, title.isEmpty { return .titleNotEmpty }
        if categoryID != nil && !categoryExists { return .categoryNotFound }
        return nil
    }

    /// Applies the rules in the reference's order and names the first one the input fails on, or
    /// `nil` when it fails none.
    ///
    /// - Parameters:
    ///   - url: The url as the command read it.
    ///   - categoryID: The category the command resolved, which the guard reads as a positive
    ///     number.
    ///   - urlIsAbsolute: The answer the URL rules give for `url`.
    ///   - feedURLExists: The duplicate answer for this account and this url.
    ///   - categoryExists: The answer for whether this account has the resolved category.
    /// - Returns: The first rule the input fails on, or `nil`.
    public static func validate(url: String, categoryID: Int, urlIsAbsolute: Bool,
        feedURLExists: Bool, categoryExists: Bool) -> FeedValidationRule? {
        if url.isEmpty || categoryID <= 0 { return .mandatoryFields }
        if !urlIsAbsolute { return .invalidURL }
        if feedURLExists { return .alreadyExists }
        if !categoryExists { return .categoryNotFound }
        return nil
    }
}
