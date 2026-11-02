// SPDX-FileCopyrightText: Copyright The Miniflux Authors. All rights reserved.
// SPDX-License-Identifier: Apache-2.0
// Ported from Miniflux internal/reader/sanitizer (Apache-2.0); adapted for Swift/SQLite.

import Foundation
import Testing
@testable import RivuletCore

/// The rules the port now models for the table modes: `inCaptionIM` (`parse.go`:1549), the mode a
/// nested table gives back through `resetInsertionMode` (`parse.go`:449), and the `table` start tag
/// that closes an open table and reads itself again in the mode the stack gives.
///
/// Every expected value is the reference's own output for its input, written by running Miniflux
/// v2.3.3 at commit `c4d54f87` on Go 1.26.0 — the toolchain `go.mod` pins — through the reference's
/// test helper options, `OpenLinksInNewTab: true` with what `config.NewConfigOptions()` gives, and
/// the base URL `http://example.org/` the other sanitizer suites read attribute values against, the
/// method recorded in `docs/testing.md`. A failure here is a difference in the implementation under
/// test, and recording it in `docs/parity.md` is the only way a difference can stay. No case reads
/// a clock, a locale or the network.
///
/// Each case names the rule it pins and can fail on that rule. Membership of the list is pinned
/// from both sides: `th` pins a name the caption mode's list does not have, and `tr` pins one it
/// does, because a name in the list moves the token after it out of the caption. The other members
/// pin that same rule, so a case for each of them would repeat the pin rather than add one. What
/// cannot be pinned is named here: the end tags the caption mode ignores, which the port already
/// ignores whatever its own list says, because none of those names is open on the stack (`body` and
/// `html` are answered before the table rules); `clearActiveFormattingElements`, which the port has
/// no list for; the failure branch of `popUntil(tableScope, caption)`, which needs a caption
/// outside the table scope, and so needs the scope markers the port does not have; the column-group
/// mode, which the port keeps as the table mode; and content that is not whitespace, because the
/// port puts content at the open element while the reference foster-parents it outside the table,
/// so a case that shows where the insertion point is can only be built on whitespace or on a start
/// tag from the mode's own list.
@Suite struct SanitizerTableModeTests {
    private let options = SanitizerOptions(openLinksInNewTab: true)

    private func sanitize(_ input: String) -> String {
        Sanitizer.sanitize(baseURL: "http://example.org/", rawHTML: input, options: options)
    }

    /// `th` is in the cell mode's start-tag list and not in the caption mode's, so inside an open
    /// caption it is read by the rules for the body, where it is a table-only tag and not an
    /// element. It pins which names the list does not have.
    @Test func thIsNotInCaptionStartTagList() {
        #expect(sanitize("<table><caption>x<th>y</caption></table>") ==
            "<table><caption>xy</caption></table>")
    }

    /// A name the list does have is pinned the same way, from the other side: `tr` closes the open
    /// caption, so the `tr` node is written at the table and the whitespace inside it belongs to
    /// the row. An implementation without `tr` in the list writes no `tr` at all, so this fails on
    /// membership rather than on the table rules the port already has.
    @Test func trIsInCaptionStartTagList() {
        #expect(sanitize("<table><caption> x<tr> </tr></table>") ==
            "<table><caption> x</caption><tr> </tr></table>")
    }

    /// The caption end tag closes the open caption, so the whitespace that follows it is written by
    /// the table rules at the table, not inside the caption. The content has to be whitespace: any
    /// other token outside the caption is foster-parented, which is not modelled.
    @Test func captionEndTagClosesTheOpenCaption() {
        #expect(sanitize("<table><caption>x</caption>\n</table>") ==
            "<table><caption>x</caption>\n</table>")
    }

    /// A nested table inside a cell is not in the start-tag list the cell mode answers for, so it
    /// is read by the rules for the body, which put the node on the tree and switch the mode to the
    /// table rules. Without that switch the nested table has no content of its own.
    @Test func nestedTableSwitchesTheModeToTheTableRules() {
        #expect(sanitize("<table><tr><td><table><tr><td>x<td>y") ==
            "<table><tr><td><table><tr><td>x</td><td>y</td></tr></table></td></tr></table>")
    }

    /// `resetInsertionMode`: the mode is the nearest table element in the open stack, so after the
    /// nested table is closed the cell is open again and a start tag from the cell list closes it.
    /// The start tag is what makes the rule visible: a case with only whitespace after the nested
    /// table writes the same string whether the mode is taken from the stack or not, because the
    /// port puts text at the open element, and the open element is the cell either way.
    @Test func tableEndTagGivesTheModeBackToTheEnclosingCell() {
        #expect(sanitize("<table><tr><td><table><tr><td>x</td></table><td>y</td></tr></table>") ==
            "<table><tr><td><table><tr><td>x</td></tr></table></td><td>y</td></tr></table>")
    }

    /// The `table` start tag read in the table mode closes the open table and the token is read
    /// again in the mode the open stack gives, which is the body here, so the two tables are
    /// siblings. The content has to be whitespace: anything else is foster-parented before the
    /// table, which is not modelled, so the case would name two rules.
    @Test func tableStartTagInTableModeClosesTheOpenTable() {
        #expect(sanitize("<table><table>\n</table></table>") == "<table></table><table>\n</table>")
    }
}
