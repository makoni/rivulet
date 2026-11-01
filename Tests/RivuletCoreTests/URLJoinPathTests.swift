import Foundation
import Testing
@testable import RivuletCore

/// Joining a base URL with a path element, as the reference does for the default icon
/// (`internal/urllib/url.go`, `JoinBaseURLAndPath`, which is Go's `url.JoinPath`); the upstream
/// cases in `url_test.go` are named per case.
///
/// What these pins can fail on, each checked by patching the rule and reverting: the two guards the
/// reference has before it joins — an empty base and an empty path are errors — and a base its
/// parse cannot read is an error, so a patch that joins anyway fails those cases; the join
/// works on the escaped path, so a patch that joins the decoded path fails the case that keeps
/// a percent escape as it was read; sequences of slashes are reduced to one; a `.` element is
/// dropped and an inner `..` removes the element before it; a `..` that begins a rooted path
/// cannot go above the root; the trailing slash survives only when the last element has one, so
/// a patch that keeps the base's trailing slash fails the case that says it does not; and the
/// base's query is kept after the joined path.
///
/// What they cannot fail on: the reference's error wording, which this port keeps as typed
/// cases, and the escaping rules themselves, which the URL layer's own suite pins — the join is
/// pinned only on that it does not escape what it joins, which is Go's documented rule that the
/// elements are expected to already be escaped.
@Suite struct URLJoinPathTests {
    @Test(arguments: [
        // Ported from `TestJoinBaseURLAndPath`, the two cases the upstream test calls valid.
        ("https://example.com", "/api/bookmarks/", "https://example.com/api/bookmarks/"),
        ("https://example.com/subfolder", "/api/bookmarks/",
            "https://example.com/subfolder/api/bookmarks/"),
        // The case the finder uses: the root URL always ends with a slash, so the join
        // adds one there.
        ("https://example.org/", "favicon.ico", "https://example.org/favicon.ico"),
    ]) func joiningAnElementToTheBase(baseURL: String, path: String, expected: String) throws {
        #expect(try join(baseURL, path) == expected)
    }

    @Test func theGuardsRunBeforeTheJoin() throws {
        // Ported from `TestJoinBaseURLAndPath`, the three cases the upstream test
        // expects an error from. The upstream value it names an invalid base URL has an
        // empty path too, so the guard is the rule that upstream test reads; the parse
        // failure is read here through a control character, which Go's `url.Parse`
        // refuses and this port's parse refuses for the same reason.
        #expect(joinError("", "/api/bookmarks/") == .emptyBaseURL)
        #expect(joinError("https://example.com", "") == .emptyPath)
        #expect(joinError("https://example.org/a\nb", "favicon.ico")
            == .invalidBase(.controlCharacter("\n")))
    }

    @Test func sequencesOfSlashesAreReducedToTheSeparator() throws {
        // Go's `path.Join`, which `url.JoinPath` joins with. The double slash here is in
        // the base path, which the parse keeps as part of the path.
        #expect(try join("https://example.org//icons/", "favicon.ico")
            == "https://example.org/icons/favicon.ico")
    }

    @Test func dotElementsAreCleanedBeforeTheJoinIsWritten() throws {
        // A `.` element is dropped and an inner `..` removes the element before it,
        // which is what takes `b` out of the path here.
        #expect(try join("https://example.org/a/./b/../", "favicon.ico")
            == "https://example.org/a/favicon.ico")
    }

    @Test func aParentElementCannotGoAboveTheRoot() throws {
        // A `..` that begins a rooted path has nothing to remove, so the root stays.
        #expect(try join("https://example.org/", "../favicon.ico")
            == "https://example.org/favicon.ico")
    }

    @Test(arguments: [
        // The trailing slash is kept only when the last element carries it: Go cleans
        // the join and then puts one back for the last element, so the base's own
        // trailing slash does not survive a plain element.
        ("https://example.org/a/", "b/", "https://example.org/a/b/"),
        ("https://example.org/a/", "b", "https://example.org/a/b"),
    ]) func trailingSlashFromTheLastElement(base: String, path: String, expected: String) throws {
        #expect(try join(base, path) == expected)
    }

    @Test func theBaseQueryStaysAfterTheJoinedPath() throws {
        // `url.JoinPath` copies the parsed base and only replaces its path, so the query
        // is not part of the join.
        #expect(try join("https://example.org/a?x=1", "favicon.ico")
            == "https://example.org/a/favicon.ico?x=1")
    }

    @Test func theJoinDoesNotEscapeButTheRenderingWritesThePathThroughTheEscapingRules() throws {
        // The elements are joined as they were read, which is what keeps a base path
        // read as `a%2fb` from becoming two elements: Go records that form as the raw
        // path because re-encoding the decoded value does not produce it again. An
        // element written unescaped is joined unescaped, but a character the path mode
        // escapes is written escaped when the URL is rendered, which is what a space
        // becomes.
        #expect(try join("https://example.org/a%2fb", "c") == "https://example.org/a%2fb/c")
        #expect(try join("https://example.org/", "a b") == "https://example.org/a%20b")
    }

    private func join(_ baseURL: String, _ path: String) throws -> String {
        try URLJoinPath.join(baseURL: baseURL, path: path)
    }

    /// Reads the branch the reference reports, not its message.
    private func joinError(_ baseURL: String, _ path: String) -> URLJoinError? {
        do {
            _ = try URLJoinPath.join(baseURL: baseURL, path: path)
            return nil
        } catch let error as URLJoinError {
            return error
        } catch {
            return nil
        }
    }
}
