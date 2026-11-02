// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import Testing
@testable import RivuletCore

/// The sanitizer fixture corpus: the two HTML fixtures read end to end against the reference's own
/// output.
///
/// Upstream reads these files only in `BenchmarkSanitize` and `BenchmarkTruncateHTML`, so no Go
/// test states what the sanitizer writes for them. Every golden file is the reference's own output
/// for the fixture bytes, written by running Miniflux v2.3.3 at commit `c4d54f87` on Go 1.26.0 —
/// the version `go.mod` declares — through the reference's test helper options, `OpenLinksInNewTab:
/// true`, with the options `config.NewConfigOptions()` gives, the method recorded in
/// `docs/testing.md`. The base URL a case uses is the one the reference's own benchmark pairs with
/// that file, because the URLs the sanitizer resolves attribute values against it. Re-running the
/// reference on that toolchain reproduces both goldens byte for byte.
///
/// A failure here is a difference in the implementation under test, and recording it in
/// `docs/parity.md` is the only way a difference can stay. The assertion compares the whole
/// document, so it names the rules the document exercises rather than one value, and each of those
/// rules can fail alone: the `github` document exercised nothing the port did not already have, and
/// the `wikipedia` document exercises the caption end tag and the mode the open stack gives back
/// after a nested table closes, which are pinned case by case in `SanitizerTableModeTests`. No case
/// reads a clock, a locale or the network.
@Suite struct SanitizerFixtureCorpusTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)

    /// Each case names the fixture, the golden the reference produced for it, and the base URL the
    /// golden was written with.
    private static let corpus = [
        ("miniflux_github.html", "miniflux_github.html.golden.txt",
            "https://github.com/miniflux/v2"),
        ("miniflux_wikipedia.html", "miniflux_wikipedia.html.golden.txt",
            "https://fr.wikipedia.org/wiki/Miniflux"),
    ]

    @Test(arguments: corpus) func fixtureMatchesItsGolden(fixture: String, golden: String,
                                                          baseURL: String) throws {
        let input = Fixtures.utf8(try Fixtures.data("sanitizer/\(fixture)"))
        let expected = Fixtures.utf8(try Fixtures.data("sanitizer/golden/\(golden)"))
        #expect(Sanitizer.sanitize(baseURL: baseURL, rawHTML: input, options: options) == expected,
            Comment("fixture: \(fixture) base: \(baseURL)"))
    }
}
