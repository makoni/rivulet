# Parity notes

Where Rivulet differs from Miniflux, and why. Reference-verified behavior itself lives in
[reference-notes.md](reference-notes.md); this file records the places where the port knowingly
diverges — because a platform facility behaves differently, or because the reference does something
we choose not to copy. Stage 7 consolidates and re-checks these notes.

## Charset decoding (stage 3)

**Matching the reference.**

- The WHATWG label table is transcribed from `golang.org/x/text` `encoding/htmlindex` (BSD-3-Clause,
attributed in `NOTICE`) — the same data the reference resolves labels against, including the aliases
the IANA registry gets wrong (`iso-8859-1` → windows-1252, `gb2312` → GBK, `utf-16` → little-endian,
`iso-2022-kr` and `hz-gb-2312` → replacement). `miniflux/go.mod` pins v0.40.0, and the 228 labels in
the port are checked against the module cache at that pinned version: every label resolves to the
encoding the port maps it to.
- A document that is already valid UTF-8 is never converted, whatever label it declares; a wrong
prolog cannot double-encode it. An unknown label is only an error when the bytes are not valid
UTF-8.
- Detection follows the reference order: BOM → content-type `charset` → `<meta>` prescan over the
first 1024 bytes → "looks like UTF-8" heuristic → `windows-1252` default. A `utf-16` `<meta>` and
the heuristic leave the bytes as they are, because the reference uses `encoding.Nop` there.
- The UTF-8 path replaces each maximal subpart of an ill-formed subsequence with one U+FFFD, the way
`x/text`'s `utf8Decoder` does. This is what makes the output always valid UTF-8, and the tests pin
the boundaries of the W3C error table (overlong forms, surrogates, forms above U+10FFFF, sequences
cut off by the end of the document).
- Undefined positions of single-byte encodings become U+FFFD, like the reference decoders; the test
pins the windows-1252 positions (`81`, `8D`).
- A UTF-16 byte-order mark is kept in the output as U+FEFF, matching the reference's `IgnoreBOM`
decoder policy.
- `x-user-defined` (high bytes → U+F780–U+F7FF) and the replacement encoding (one U+FFFD) are
implemented directly.
- `hasUTF8XMLDeclaration` compares the declared value with `utf-8` ASCII-only, as the reference's
`bytes.EqualFold` does, so the valid alias `utf8` is not recognized there.

**Known differences.**

| Case | Reference (`x/text`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Big5 byte `80` | U+FFFD | U+0080 (ICU/Foundation) | A private byte survives where the reference
drops it | | Big5 byte `FF` | U+FFFD | U+F8F8 (ICU private use) | An invalid byte becomes a PUA
character instead of U+FFFD | | Invalid sequences in GBK/GB18030/Big5/Shift_JIS/EUC-KR/ISO-2022-JP |
U+FFFD per maximal subpart, which can cover several bytes | platform decoder, then glibc `iconv`
(which reports one error per stop), then the UTF-8 replacement rule when the platform has no
converter | Corrupt spans can differ in the number and placement of U+FFFD; valid text is unaffected
| | EUC-JP on Linux | decoded by `x/text` | Foundation returns `nil` for every input, so the glibc
`iconv` fallback decodes it | Same result for valid documents; pinned by a test | | Single-byte
tables | `x/text` `charmap`, so `iso-8859-8-i` keeps its own visual table and `iso-8859-6` its own |
CoreFoundation resolves the IANA name, which can map an alias to a different table (for example
`iso-8859-8-i`) | Only exotic input differs; no fixture covers it | | `<meta>` prescan | full HTML
tokenizer, with character references unescaped in attribute values and the vertical tab as
whitespace | tag scanner (comments, quoting, attribute order, 1024-byte window) | Malformed markup
the tokenizer recovers from can end the scan; a label written as an entity is not resolved | |
Content-type `charset` parameter | `mime.ParseMediaType` | direct parameter scan | Some malformed
headers yield a charset where the reference falls through to detection |

None of these differences is observable on the ported fixture corpus: all fixture assertions the
reference makes are reproduced. Valid documents in a legacy encoding decode identically.

## XML reader (stage 3)

**Matching the reference.** The buffer rules, `space`, `attrval`, `text`, the comment, CDATA and
directive reading, `getc` and `mustgetc`, the namespace scope and the end-of-root rule follow
`encoding/xml` (Go 1.22) line by line, with the configuration Miniflux builds (`Strict = false`,
`Entity = xml.HTMLEntity`). `ungetc` is an equivalence rather than the same function, since the
reference never reads after a failure. The name classes are the one approximation, recorded in the
table below. The entity table is transcribed from it and attributed in `NOTICE`.

The four quirk classes — the byte-order mark, garbage before the prolog, character references and
`<![CDATA[` — were checked by running the reference over 52 inputs through the reader path, and no
difference was found, so `docs/reference-notes.md` records the rules as the reference reports them
and the pinned corpus cases name them. The end of the stream is the one thing those pins cannot tell
apart, and it is the equivalence recorded below, where the reference's bare `io.EOF` and its
`unexpected EOF` are the same case here.

The parser path was checked the same way over ten inputs — the sentinel, the branch the switch takes
for it, and how the scan ends, where the recorded end states are the reference's own messages — and
there too no difference was found, so `docs/reference-notes.md` records the rules as the reference
reports them.

**Known differences.**

| Case | Reference (`encoding/xml`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Name classes | two explicit `unicode.RangeTable`s (`first`, `second`), a transcription of an older
Unicode version | Swift Unicode properties: letter, number and grapheme-extend, plus the ASCII name
bytes and `-`, `.`, `·` | Go's tables omit letters Swift reports as letters (`ª`, `µ`, `º`, the
ligature and digraph forms) and most characters above the BMP, so Rivulet accepts names the
reference rejects. No fixture covers it | | `text` rejects invalid UTF-8 | reports `invalid UTF-8`
for a rune it cannot decode | not modeled: invalid sequences are removed before the document is
read, so the check is reached only when the label is never resolved, which is the case in the next
row | The reference fails such a document, Rivulet filters it; pinned by a test | | Label |
`procInst` is applied to an instruction token, so the label is the one carried by the first
instruction whose target is `xml`; Miniflux decides the path from the first `encoding=` of the whole
document, which is not the same lookup | the same, with the two lookups kept apart: the path is
decided by the first `encoding=` anywhere, the label is read from the first instruction with the
target `xml` | A body `encoding=` decides the path but is never resolved, so such a document fails
in the reference and is filtered here; pinned by a test | | Instruction start | `procInst` is
reached at a token boundary, so a `<?` inside a comment, a CDATA section or a quoted attribute value
is not an instruction | the label scan reads `<?` occurrences in the bytes, so one inside markup
counts | A Latin-1 document whose only `encoding=` is inside a comment converts here and fails in
the reference; pinned by a test | | Where the conversion applies | `switchToReader` converts from
the instruction on, so bytes read before it are not converted | the label is applied to the whole
document | Bytes before a late `xml` instruction that are not valid UTF-8 fail in the reference and
are decoded here; pinned by a test | | End of document inside a name or an unquoted value | fails,
because `mustgetc` cannot read past the end | fails as `unexpectedEOF` | Same result; the difference
is only in the message, which is not modeled | | Error reporting | `SyntaxError` with a line number
and a message | typed `XMLError` cases, no line numbers | Callers match on the case, not on the text
| | Bare `io.EOF` | returned as it is when the stack is empty, such as after a comment at the top
level, or when it is at the record `pushEOF` put; `Token` converts it otherwise, and `mustgetc`
converts it on every read that finds it | the same `unexpectedEOF` case, because the port keeps one
failure | Only the message differs; the reader reports it as one failure | | `translate`'s
`DefaultSpace` | falls back to the decoder's `DefaultSpace` for a name with no prefix, which the
reference sets to `rss` for this format (`internal/reader/rss/parser.go`) | the same, as the match
takes a default space: `XMLName.matches(local:namespace:defaultSpace:)`. A declared default
namespace wins, because `translate` substitutes only for a name that had no prefix | A feed with a
declared default namespace reads empty in both, which is pinned as a test | | `AutoClose` | a list
the reference can be given, which invents end tags for unclosed elements | not ported, because the
reference never sets it | None | | `pushEOF` and `popEOF` | used by `unmarshalInterface`, so only
for values whose type implements `UnmarshalXML`; Miniflux implements it for two types
(`internal/reader/rss/rss.go:210`, `internal/reader/opml/opml.go:75`) | not ported, because this
layer reads tokens and not values; the marker marks where `unmarshal` stops for a value read as a
plain struct | The reference fails a value implementing `UnmarshalXML` that stops before its end tag
(Go's `read.go:218-220`); nothing here checks that, because there is no value layer | | `Inner`
(`",innerxml"`) | the bytes the tokenizer read, so a run inside it keeps the entities as they were
written, and a comment, a directive or an instruction inside the element is part of it | a
reconstruction from the tokens: the markup plus the text, with the text already decoded, and with
comment, directive and instruction tokens kept out of the content | `rssAuthor.Inner` decides its
branch on `<![CDATA[`, which the flag on the text run carries, so the branch is the reference's
rule; the text inside a reconstruction differs by the decode. Pinned by a test | | Names inside a
reconstruction | as written, because the bytes are the ones read | as the tokenizer resolved them,
because the tree keeps the resolved name | A document with an aliased prefix writes the resolved
namespace here; no fixture covers it | | The two ways of reading an element | `",chardata"` is the
character data at the element's own level, while `innerContent` (Miniflux's own type,
`internal/reader/xml/decoder.go`) collects every character token, including the ones inside a child
| the same two, kept apart as `XMLElement.text` and `XMLElement.innerContent`, which is why content
is stored in document order | None; the difference between the two is pinned by a test |

## Date parsing (stage 3)

**Matching the reference.**

- The layout catalog is transcribed verbatim: the three constants of the local-time group, then the
206 layouts in the order the reference tries them, with the entries it repeats left repeated. The 79
normalization pairs are transcribed in order, matched at a position by the priority Go gives them,
which is the order the pairs are listed in. The only pair whose pattern is a prefix of another is
`Mai`, and the longer `Mai ` is listed before it, with the same trailing space in its replacement,
so the two rules give the same output for every input, and the scan advances by the pattern length
rather than by the replacement.
- The reading primitives (`skip`, `getnum`, `getnum3`, `lookup`, `atoi`, `parseTimeZone`,
`parseGMT`, `parseSignedOffset`, `parseNanoseconds`) follow Go 1.22 `time/format.go` line by line,
over UTF-8 bytes: a layout space matches a run of spaces, `lookup` is a case-insensitive ASCII
prefix match, and a fractional kind keeps only the digit count because `parseNanoseconds` accepts
`.` or `,` whichever the layout writes. `atoi` accepts a leading sign, which is what lets the
two-character year read `+6` and an exact fractional run read `.+5`, while `getnum` does not, so the
offset fields take digits only; `parseNanoseconds` reports a negative result as out of range.
- The zone resolution keeps Go's sentinel: `zoneOffset` starts at −1 to mean "no offset was read",
so a value of exactly −1 second is read as no offset at all, and the zone falls back to the default
location, which is UTC in both.
- A value that reads no zone is read as UTC, which is what the reference does too: `time.Parse` is
`parse(layout, value, UTC, Local)`, so its default location is UTC, and `parseLocalTimeDates` pins
UTC for its three layouts as well. The machine's zone is consulted only when a name or an offset was
read, which is the fixed table below.
- Go's `RFC3339` fast path is not ported, and that changes nothing at all: `Parse` falls back to the
general `parse` when `parseRFC3339` fails, so an unpadded field is accepted either way, and for a
value the fast path accepts the result is the same as the general path's, location included. The
only place where the port and the reference can differ for such a value is the fixed zone table.
- Field ranges are the reference's: 0–23 for the twenty-four-hour pattern and 0–12 for the
twelve-hour ones, since twelve is noon or midnight; minutes and seconds below 60; the day validated
against the month; the year-day 1–365 with the leap-year decrement; and the two-digit year split at
69.
- Day counting is Go's proleptic Gregorian `Date`, checked against `daysBefore`, `daysIn` and
`daysSinceEpoch` for every date in years 0 through 9999, which is the range the four-digit pattern
reads; a layout with no date leaves year 0 behind, and a `Calendar` is not involved. The suite pins
the leap-year and year-day cases rather than the whole range.
- `checkTimezoneRange` belongs to the entry point, not to the engine: an offset outside −12:00 to
+14:00 is reported as UTC with the instant unchanged, so the engine reports what the layout read
even for an out-of-range offset.
- An input that reads as an integer is taken as a Unix timestamp before any layout, which is the
instant the reference reports; `Int64(text)` accepts a leading `+` as `strconv.ParseInt` does. Go
keeps its local zone for that result, so the zone it reports is the machine's, while the port
reports UTC with offset 0. The "now" fallback the reference's adapters use is not this entry
point's, because it needs a clock.

**Known differences.**

| Case | Reference (Go 1.22 `time`, the version these notes were traced against) | Rivulet | Impact
|
| --- | --- | --- | --- |
| Zone abbreviations | `lookupName` asks the machine's local `Location`, so the offset depends on
the instant and on tzdata; the reference's `PST`/ `PDT` and `EST`/ `EDT` names resolve through Los
Angeles and New York at the parsed instant | a fixed table: `PST` −28800, `PDT` −25200, `EST`
−18000, `EDT` −14400, `UTC` and `GMT` 0, `GMT±hh` from the name, and the documented fallback 0 for
everything else | An abbreviation the machine's zone knows resolves to a different offset here, and
a name read inside a daylight-saving period keeps the standard offset instead of the daylight one. A
value that reads no zone is not affected, because both read it as UTC | | Zone name | `Zone()`
reports the name of the resolved `*Location`: the machine's zone when it was in effect at the parsed
instant, otherwise a fabricated zone named by the name as read | the name as read, which for a bare
numeric offset is the empty string | Upstream assertions on `Location().String()` cannot be
reproduced; the names are pinned as read, and the two agree when Go fabricates the zone, or when the
machine's abbreviation at that instant is the name as read | | Version of `time` | the reference is
Miniflux v2.3.3, whose `go.mod` declares Go 1.26; a current `time` accepts a literal `Z` for all
five ISO patterns and rejects an offset hour above 24, an offset minute above 60 or an offset second
above 60 | Go 1.22 `time/format.go`, which these notes were traced against: `Z` for the three
patterns that carry no seconds, and no range check inside a numeric offset | `+25:00`, `+01:61` and
`+01:00:61` match here and are rejected by a current Go, while `+24:00`, `+01:60` and `+01:00:60`
match in both because those checks use `>` rather than `>=`. A 1.22-only match outside
`checkTimezoneRange`'s −12:00 to +14:00 is reported as UTC with the instant preserved, while
`+01:61` is inside the range and keeps its offset. The `Z` half cannot be reached through the
catalog, whose 209 layouts have no seconds-bearing ISO pattern | | Trimming | `strings.TrimSpace`,
which also trims Unicode whitespace | Go's `asciiSpace` set | Input that starts or ends with a non-
ASCII space is trimmed there and left as it is here | | A layout that does not match | a
`ParseError` naming the layout, the layout element and the value element | no match, because the
reference only cares whether a layout matched; the entry point reports the failure after the last
layout | The text differs; which layout matched, and the value it read, are the same |

## URL layer (stage 3)

**Matching the reference.**

- The parse order is Go's: the fragment is cut first, then the scheme, then the query, then the
opaque form or the authority, then the path. The control-character check is made on the part before
the fragment, which is where Go makes it.
- Only a colon at the start of the value is a failure. An invalid character before the colon means
there is no scheme, and the value is read as a path; a relative value whose first segment carries a
colon is the error Go reports for a value like `cache_object:foo/bar`.
- The scheme is lower-cased, as Go lowercases it after reading it, so `RootURL` and the rebuilt
string report it lower-cased whatever the input case was.
- A raw form is recorded only when it is not already the canonical encoding of the decoded value,
which is Go's rule for `RawPath`, and `EscapedPath` refuses a recorded form it cannot decode back to
the decoded value. That is what keeps `http://golang.org/a%2Fb` as it was written while
`http://golang.org/a%20b` has no recorded form at all.
- The escape classes are the ones `gen_encoding_table.go` builds the table from: alphanumerics and
the marks `-` `_` `.` `~` are never escaped; the path escapes only `?` from its reserved set, a
query component escapes all of it, a fragment escapes none of it, and a host allows the
sub-delimiters plus `:` `[` `]` `<` `>` `"`. A `+` is a space only for a query component.
- `validEncoded` allows the sub-delimiters whatever the mode says, because `shouldEscape` is not
quite RFC 3986 compliant, which is what decides whether a recorded raw form is used.
- The host is read through the host mode, so a byte at or above DEL is part of it and a percent
escape may only carry one — except `%25`, which carries the percent sign of a zone identifier — and
the host is stored decoded, as Go stores it. So `http://foo%c3%a9bar/` parses and reports the
decoded host.
- The port is read at the first colon for `http` and `https` and at the last one for another scheme,
which is Go's strict-colon rule with its default on; with the `urlstrictcolons` setting off Go takes
the last colon there too. A bracket that opens inside the host is refused.
- The user part is checked against the class RFC 3986 §3.2.1 allows, and Go does that after the host
is read, so a value with both a bad host and a bad user reports the host.
- Query pairs: only `&` separates them, a pair carrying a `;` is an error that `Query()` discards, a
pair with no `=` is a key with an empty value, and a malformed escape skips the pair. `Encode()`
writes the keys sorted, with the values of one key in the order they were read.
- `ResolveReference`: a reference that carries an authority is returned as read after its path is
cleaned; a reference with no path and no query takes the base query and fragment; otherwise the path
is joined through `resolvePath`, which removes dot segments, pops the whole segment before a `..`,
keeps a trailing slash when the value ended with a slash or with a dot segment, and does not
collapse a doubled slash.
- `Hostname` reports a bracketed host without its brackets, and a host whose port is not a number is
not split at all, which is what Go reports in that case too.
- `ForceQuery` (a value ending with a single `?`) and `OmitHost` (a scheme followed by a slash path
with no authority) are ported, because both change the string the sanitizer writes back into an
attribute, and `ResolveReference` does not hand `OmitHost` to the value it resolves.

**Known differences.**

| Case | Reference (`net/url`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Bracketed host | must be a valid IP literal — `netip.ParseAddr` over the unescaped name, with an
IPv4 inside brackets refused, and a zone identifier read through its own mode | the bracketed name
is read through the host mode and decoded, but only the port after it is checked | A bracketed host
that is not an address parses here, so the reader resolves it as a name and the fetcher's address
policy sees a host to look up instead of a value it would refuse | | Percent escapes of bytes that
are not valid UTF-8 | the bytes are kept as they are, since a Go string can hold them | a Swift
string is valid UTF-8, so a decoded byte that is not a valid sequence becomes U+FFFD | Only an
escape of bytes that are not a valid UTF-8 sequence differs; a host can carry such an escape,
because the host mode allows an escape of a byte at or above DEL | | Query parameter count |
`ParseQuery` refuses a query above its limit | no limit | A query with more pairs than the limit is
parsed here | | The `*` path | `EscapedPath` returns `*` unescaped | escaped as `%2A` | Only the
request-URI form, which the reader never resolves | | Authority user part | `Userinfo` keeps the
username and password decoded separately and re-escapes them when the string is rebuilt | the user
part is kept as it was read | The rebuilt string can differ for an escaped user part; nothing in the
reader uses the split | | Error wording | sentences such as `invalid port %q after host` and
`missing protocol scheme` | cases naming the offending character, port or escape, with the escape
named as Go names it — at most three bytes of it | The text differs; which value fails is the same,
and the reader acts on the failure, not on the text |

## HTML sanitizer (stage 3)

**Matching the reference.**

- The sanitizer does not read through SwiftSoup, which the stage 3 plan named for it. The output the
reference writes is the string it builds itself — the element name, then the attributes in the order
they were read, except for a formatting element, which is the case below — so attribute order, name
lowercasing, entity decoding, the raw-text states and the open-element depth guard have to be the
port's own. SwiftSoup does not expose the attributes it parsed (`Node.attributes` is internal to the
module), it has no depth guard at all, and its tree builder is not the one the reference's rules are
read against. SwiftSoup is still the dependency `EntryText` uses.
- The tokenizer and the insertion modes are traced against `golang.org/x/net/html` (BSD-3-Clause).
`miniflux/go.mod` pins v0.57.0, which is what the reference parses with, and the copy the rules were
read from is the module cache at that version, which is also what a corpus value can be checked
against, since the reference runs with it. `Tests/RivuletCoreTests/HTMLTokenizerTests.swift` pins
the tokenizer: the comment state is entered only through the two dashes of `<!--`, and a comment
closes only after two dashes (`-->` or `--!>`), so a `>` inside its data is data; a doctype, a
processing instruction and any other `<!` or `<?` close at the first `>`. A tag name, an attribute
key and an attribute value have NUL replaced with U+FFFD, which `TagName` and `TagAttr` do, while a
text token has it removed by the insertion mode, because the tokenizer flags only CDATA and the
raw-text state as converting, and `Text()` converts a comment through its own check. A named
reference without its semicolon is resolved outside the attribute mode only, and the semicolon stays
part of the name because the reader is already past the character it stopped on, which a name
outside the 106 short names shows. A duplicate attribute name is kept once. `readTagAttrVal` skips
whitespace before the `=`, and a solidus after the `=` is the unquoted value. `>`, `<` and a nested
tag inside a raw state are data, which the content of the two raw states that are still written
(`title`, `textarea`) shows. A newline at the start of a `pre` or `listing` block is dropped when it
is the first thing in the data as the token was read, before the NUL is removed, and the escape
forms are `&#34;`, `&#39;` and `&#13;`, pinned in text and in an attribute value. Four pins cannot
be seen through the sanitizer output and are asserted through the tokenizer itself: the tag name and
the attribute key carrying a NUL, the shape of the entity table, and where comment data ends,
because the renderer writes nothing for a comment. `Tests/RivuletCoreTests/SanitizerTests.swift`
pins what the insertion modes answer with: `</p>` with no open `p` in `buttonScope` inserts an empty
one, and `</br>` is read as a start tag. Only `hr` and the block list close an open `p` — `button`
does not, and `br`, `img` and `wbr` do not, and `table` pops `p` only outside quirks mode, which is
never the case on the reference's path. `td` and `th` outside a table are not elements at all, while
inside one the escaped attribute value is written, and `</table>` switches back to the insertion
mode for the body, so content after it is not table content. The scope walk stops at the scope's own
stop tags and at `defaultScopeStopTags`, and the second half needs a stop tag above the match: a
`</p>` cannot reach an open `p` through the cell, so it writes an empty `p` at the cell.
`listItemScope`'s own stop tags are `ol` and `ul`, which the default list does not have, and that is
pinned by an `li` under an inner list. An end tag outside the block list walks the stack and stops
at the first special element, which is a different set from the stop tags: `p` is special but is not
a default stop tag, and `span` is neither, so a `</span>` inside a `p` is ignored and the text that
follows stays in the `p`. A start tag or an end tag that the current table mode does not name is
processed by the rules for the body at the insertion point, so an `img` inside a cell is written
into the cell and `</p>` puts an empty `p` there. A section start tag pops the open section element
before the token is read again in the table mode, and the case has to open `thead`, because that is
a name the renderer writes: `tbody` is not in the allowlist, so a case built on `tbody` writes the
same string whether the pop happens or not.
- `addFormattingElement` is the one place the reference reorders the attributes it puts on a node:
it sorts them by namespace, then by name, then by value. The port has no namespace, so the name and
the value are the whole comparison, and the sort is applied for the names `inBodyIM` answers with
that function. `a` is the only one of those names with attributes in the sanitizer's allowlist, so
the order shows in the output through an `a`; `img` has two attributes and is not a formatting
element, which is the case that keeps the two apart. The rule is pinned by the hostile corpus, and
the reference applies it only on the body path — see the foreign-content row below. The same corpus
pins the limit of 512 open elements the port models as `Failure`: the reference reaches it by
panicking and `html.Parse` recovers that as an error, so both answer with nothing.
- The srcset descriptor rules are ported, including the two that decide the string written back: the
density is written with `strconv.FormatFloat(value, 'g', -1, 64)`'s rule — the shortest digits that
round-trip, the exponent form when the decimal exponent is below -4 or at least 6, and the sign of a
negative zero, which the number rule accepts — and the width as `FormatUint` writes it. The integer
descriptors read through `ParseUint(value, 10, 0)`, whose range is the whole unsigned 64-bit value;
only the width is written back, so the height is observable only through the rule that makes a
height-only descriptor invalid. Both are pinned by `SrcSetParserTests`.
- The entity table is the data `x/net/html` builds from the HTML5 named character references,
generated from the module-cache copy at the pinned v0.57.0, and its shape is pinned by
`HTMLTokenizerTests`. The `entity` map has 2138 entries, 106 of them without a semicolon, and every
one of those 106 resolves to the value its semicolon form resolves to, so the table stores the 2032
semicolon forms once and the short names as a set. The 93 `entity2` entries are kept apart because
they resolve to two code points. The XML reader's table is `encoding/xml`'s smaller HTML4 set, so
the two tables are kept apart rather than merged.
- The text layer reads through the same tokenizer and writes what `Text()` gives for a text token:
the data decoded for the states that are not raw, `title` and `textarea` decoded, the other raw
states written as read, and newlines normalized. A data-state text token keeps its NUL, because
`Text()` converts only in the states the tokenizer flags as converting — the raw-text states and
CDATA — and for a comment token. `TrimSpace` and `FieldsSeq` read `unicode.IsSpace`, which answers
with the generated `White_Space` table, the UCD property, and not with the three sets its comment
names: `U+0085`, `U+00A0` and `U+2028` split a word, while `U+001E` and `U+200F` do not, and a Swift
scalar reports the same table. The trim half is pinned by `StripTagsTests` and the split half by
`TruncateHTMLTests`. The limit counts code points, which is what the reference counts.

**Known differences.**

| Case | Reference (`golang.org/x/net/html`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Foster parenting | content the table modes cannot take is attached to the parent of the table, so
it is written before the table | the insertion point is the open element, so it is written inside
the table | This is the subset boundary: no case in the reference corpus changes what the sanitizer
writes because of it, but real feeds can nest content inside a table here where the reference moves
it out | | Active formatting elements and the adoption agency | a formatting-element list and the
adoption agency algorithm, which can move a node into or out of an element | the order rule
`addFormattingElement` gives the attributes is ported; the list, the reconstruction and the agency
are not | Markup such as `<p><em>x</p>y</em>` nests differently, so the output differs; nothing in
the corpus covers it | | Attribute order inside `math` or `svg` | the sort belongs to
`addFormattingElement`, but content there is inserted through the foreign-content rules, which do
not sort | the sort is applied whatever the content is, because the foreign-content mode is not
ported | An `a` with more than one attribute inside `math` or `svg` writes its attributes sorted
here and as read in the reference; the corpus cannot pin it, so no case asserts it | | Caption, the
mode the open stack gives, and the scope markers | each mode has its own rules, including the
markers the scope checks stop at | the table modes are the scopes `clearStackToContext` answers for,
with the implied `tbody` and `tr`, and the caption mode is ported; the mode is read from the open
stack the way `resetInsertionMode` computes it, so a nested table reads in the table mode and gives
the mode back to the element around it when it closes; `colgroup` answers with the table mode,
because the column-group mode is not ported | Content inside `colgroup` nests here where the
reference closes the section, and a caption outside the table scope is not popped here; the ported
half is pinned by `SanitizerTableModeTests` | | Text inside a table | only whitespace text is added
to the table element; anything else is foster parented | added to the insertion point | Same for
whitespace; non-whitespace text can be inside the table here | | Comment nodes | kept as nodes in
the tree | not recorded at all | None, because the renderer writes nothing for them; the tree is the
shape the sanitizer sees | | A heading start tag | pops an open `h1`– `h6` before the new heading is
inserted | only the `p` pop is ported | `<h1>a<h1>b</h1>` nests the second heading inside the first
here | | `li`, `dd` and `dt` start tags | pop an open ancestor of the same kind, then `p` | the `p`
pop is ported, the ancestor loop is not | `<ul><li>a<li>b</ul>` keeps the second item inside the
first here; the end tag for `li` is ported and uses `listItemScope` | | A second `form` start tag |
ignored while `p.form` is still set | inserted | None, because `form` is not in the allowlist and
only its content is written; the string is the same either way | | The leading newline of raw text |
`textIM` drops it for `textarea` and `title` | dropped for `pre` and `listing` only |
`<textarea>\nx` keeps the newline here | | A self-closing start tag in foreign content | pops the
element it opened | the token kind is read, the insertion effect is not | `<math/>x` nests here
instead of closing `math`; the check also compares against the last *saved* attribute, where the
port tracks every value read | | A `<![CDATA[` | a CDATA token inside foreign content only, which
`AllowCDATA` answers for | a bogus comment that closes at the first `>` | `<math><![CDATA[x]]>`
writes `x` in the reference and nothing here | | Script escaping states | the script data can end at
a different position through the escaping states, which can pass a `</script>` as data | the raw
state ends at the end tag | The renderer writes nothing for `script`, but the text layer writes the
content of a raw state, so the difference is observable there: for <script><!--<script
</script>x</script> ` the reference writes `<!--<script </script>x ` and the port writes
`<!--<script x `, which `StripTagsTests ` pins | | Content in `head | read through the insertion
mode for the head, so markup there is not part of the node the renderer walks
| `html` and `head` do not put a node on the tree, so it is read in the body |
`<head><title>x</title></head>` writes `x` here and nothing in the reference | | Implied end tags |
`generateImpliedEndTags` pops `p`, `li`, `dd` and `dt` before `hr` and `button` in some cases | the
open `p` is popped, which is the same answer while the stack is well formed | A list item or
definition inside a `p` nests through the ancestor loop, which is the row above | | Positions and
counts | the tokenizer measures bytes and the character walks count runes | `Character` graphemes,
except the text layer, which walks the scalars so the count is per code point | A combining sequence
or a ZWJ sequence is one position here where the reference counts more; the `&#13;&#10;` pair is one
instance of that | | The reader error `stripIter` reports | `StripTags` and `TruncateHTML` write
nothing when the reader reports an error
| no equivalent, because the input is a string and the walk always completes | Nothing differs for
an input that is already a string; the path is only reachable through a reader | | A byte that is
not valid UTF-8 | counted as one against the limit and written as the byte it was read as | a Swift
string cannot hold it, so the value is U+FFFD | Only for input that is not valid UTF-8, which the
reader never produces, because its output is always UTF-8 | | NUL in comment and doctype data | the
flag is set only for CDATA and the raw-text state, and `Text()` converts a comment through its own
check, so a doctype keeps the NUL | converted in both | A comment and a doctype are not written, and
`stripIter` skips those kinds, so this cannot be observed | | The Vimeo `dnt=1` append | the link is
written as it was read | rebuilt from the parsed parts | A query that is not already in the
canonical form is re-encoded, so the string differs; one that is, is written the same | | `escape`
and `unescape` | `&#34;`, `&#39;` and `&#13;`, and the no-semicolon fallback outside attribute mode
| the same, pinned by tests, for a lone CR | A decoded `&#13;&#10;` is one `Character` grapheme in
Swift, so the pair is written raw where the reference writes `&#13;` and a newline |

## Format adapters (stage 3)

**Matching the reference.** An adapter fills the normalized model by matching the tree against the
namespaces the reference's field tags name, so the chains, the fallback orders and where a value is
trimmed are the reference's. The shape the struct has decides where a value is read from, which is
why the RDF items are read at the root level rather than through the channel, and a single-value
field takes the last element that matches at its own level, because the reference assigns the field
for every match. The model is ours: the fields `model.Feed` carries for the storage layer (the fetch
time, the conditional-GET headers, the error counters) are not parsing results, so they are not
modelled, and adapters do not sanitize content — sanitization is the layer after this one.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| The clock the date fallback reads | `time.Now()` for a value that is empty or cannot be parsed |
the clock is a parameter of `parse`, so the suite is deterministic; the parser itself reads no clock
in either | Only the injected value differs | | A value read through a field tag | the decoder keeps
the character data as the tokens read it, because `copyValue` assigns a string without trimming, so
the trim is the adapter's own | the same split, as `XMLElement.text` plus a trim where the adapter
applies one | None; the places where the reference does not trim before using the value — the
content, the hash inputs, and the author branch that chooses before it strips — are pinned by tests
| | The name the root must have | `Unmarshal` fails when the root name or its namespace is not the
one the `XMLName` field tag names (`encoding/xml/read.go`), and the RDF struct has such a field |
not ported, because this layer reads tokens and not values, so an adapter fills the model from
whatever root it read | Reachable through the parser, because detection matches the root on its
local name only: a root with the local name `RDF` in another namespace is routed to the RDF adapter,
where the reference fails and this reads the feed | | A field tag with no namespace | matches any
namespace, because `finfo.xmlns` is empty | the same, as a match with an empty namespace | None | |
The cache lifetime | `time.Duration`, read back as minutes | minutes, because the reference only
ever reads it as minutes | None | | The relation fold | `strings.EqualFold` takes the ASCII fast
path and folds the rest through `unicode.SimpleFold`, so `aℓternate` — with U+2113, which folds to
`l` — matches `alternate` there | the ASCII path only, so such a relation does not match here | A
relation written with a letter that folds to an ASCII letter is read as an alternate link in the
reference and not here; the ASCII path is pinned by a test | | Entry identity with a repeated GUID |
the first occurrence keeps `SHA256(guid)`, a later one uses the entry URL, and the position only
when the entry has no URL at all, which needs a base URL nothing can be resolved against | the same,
in the same order | The position branch is reached only by the traced case with an empty base URL;
with an absolute one the URL wins, which `TestParseEntriesWithDuplicateGUIDAndNoLink` pins | | The
key the media attachments are deduplicated against | the Atom media thumbnails test the map on the
URL as the element carries it, before the reference resolves it, so two spellings of one file stay
two attachments; every other group tests the resolved value, as the RSS thumbnails do | the same
split, as the key flag on `MediaRules.Candidate` that the format sets for its thumbnails | None;
both orders are pinned, in `AtomMediaTests` and `RSSMediaTests` |

### The Atom Text construct

Two readings of the same element, which the reference does not agree on, and which the tree cannot
answer the same way for every input.

- The reference keeps `innerxml` as the bytes it read, and `",chardata"` as the character data it
gathered while walking the subtree. The tree keeps character data already decoded, so `innerMarkup`
is a reconstruction: a run that carries entities comes back as the character it resolves to, not as
the reference wrote it. Cases whose stated value needs the bytes as written cannot be pinned, and
are not ported — see `docs/testing.md`.
- `",chardata"` keeps only the level the field is read at, so the text inside a child element is not
part of the value, while `innerContent` writes every character token it read. The tree keeps the two
apart, which is what the Atom content cases depend on.
- The `type` gate is `strings.EqualFold`, and the port applies the ASCII fast path, as recorded
above.

### `xml:lang`

No deviation here. The field tag is namespace-qualified and reads the attribute on the element that
carries it, and the decoder inherits nothing between elements, so the entry's value is its own
attribute and the feed's value is the root's. The entry→feed chain is the adapter's own code, ported
as it is written. `AtomLanguageTests` pins both levels and the namespace gate.

### Bytes, not characters

- `textLinkRegex` is `(?mi)(\bhttps?://[^\s]+)`. RE2 reads `\b` and `\s` as ASCII classes, while
Swift's `Regex` reads them as Unicode ones, so the port implements the rule on bytes with the ASCII
word boundary and the ASCII whitespace class Go uses. A URL that begins with a non-ASCII letter, or
that is followed by a Unicode separator, is matched by Swift's `Regex` and not by RE2 — the ASCII
behaviour is what the port keeps, and the fold and the boundary are pinned by a test.
- The Atom 0.3 base64 branch is `base64.StdEncoding.DecodeString`, which skips the two newlines and
fails on anything else the alphabet does not have. Go reports padding that is not at the end as an
error; Swift's `Data(base64Encoded:)` answers `nil` for the same input, which is the same outcome
here, because a failed read leaves the content empty.

## JSON reader (stage 3)

**Matching the reference.** Miniflux has no JSON reader code to port: its JSON adapter reads a feed
through `encoding/json`, so this layer mirrors the part of that source the reader reads through —
`scanner.go`, `decode.go` and `stream.go`, the Go 1.26 that `go.mod` pins. The positions are the
`stateX` productions. For a byte inside the value the context of a failure is the words the
production names, which is what lets a pin compare it against what the reference reports; for input
that ends the path `Decode` takes reports the end of input itself, so no context is pinned there,
and the contexts the states name belong to `checkValid`. The rules that belong to the machine are
the machine's: the four ASCII separators rather than any byte below the printable range, the escape
set `stateInStringEsc` accepts, the number states with the fall-throughs `state1` has to `state0`
and `stateE` to `stateESign`, the literal words walked letter by letter, the depth `pushParseState`
limits to, and the way `unquoteBytes` makes the bytes well-formed. No dependency is added: the
reader is our own over the bytes, because a platform JSON decoder cannot reproduce the per-field
error semantics or the leniency the reference has. The two separators the token machine reports are
the opcodes `scanObjectKey` and `scanObjectValue`/ `scanArrayValue`, which are what `Token` elides,
so they are kept because the tree is built from them.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| The path that reads the document | `Decode` — the path the reference's JSON adapter takes — reads
one value and breaks at the first `scanEnd`, so nothing after the top-level value is examined;
`Unmarshal`, which validates the whole document with `checkValid` first, does examine it and reports
the failure at the first byte after the value | the `Decode` path: for a container the byte that
closes it is the last byte read, because `readValue` tests `scanEnd` against an invented space, and
for a scalar the byte that ends the literal is read, because it is what decides whether the literal
had ended, but `stateEndTop` reports `scanEnd` for whatever it is, so the machine stops there |
`1garbage`, `1 2` and `{"a":1}garbage` read here without a failure. `Unmarshal` reports invalid
character 'g' after top-level value ` for `1garbage ` and the same for the other two, and `Decode
reports no syntax error at all for them | | An empty document | `Decode` reports `io.EOF` when
nothing was read and `io.ErrUnexpectedEOF` when a value is left open; `checkValid` reports both as
`unexpected end of JSON input` | one failure, `unexpectedEnd`, for the two | Only the error identity
separates them in the reference, and nothing in the port reads the message | | Input that ends where
a state still needs a byte | `readValue` uses the invented space only to decide whether to break, so
it reports `io.ErrUnexpectedEOF` there, while `checkValid` reports that space as invalid in the
state's context — `invalid character ' ' in numeric literal` for `{"a":-` | the end of input,
`unexpectedEnd`, which is what `readValue` reports; the context the state names is not kept | None
on the `Decode` path; a reader that validated the whole document would name the state | | Invalid
UTF-8 inside a string | `unquoteBytes` coerces the bytes to well-formed UTF-8, one U+FFFD per byte
that is not a valid encoding, because `utf8.DecodeRune` reports one byte at a time and rejects an
overlong form, an encoding of a surrogate and a form above U+10FFFF | the same checks, written out
rather than left to Swift's UTF-8 decoder, so the one-byte-at-a-time rule is the reader's own |
None; Swift's decoder answers the same for the cases pinned, so the difference is which code keeps
the rule | | The order an object keeps | `map[string]any` keeps no order and one value per key, so a
repeated key is folded and the value it holds is the last assignment | the tree keeps the members as
the document wrote them, so a repeated key stays two members; the last-wins rule is pinned in
`JSONFieldReadTests` | Order is what the field read walks, which the reference could not pin | | The
name a struct field matches | `Unmarshal` prefers an exact name match and also accepts a case-
insensitive one through `foldName` | not ported: the tree keeps the key as the machine decoded it,
so the adapter matches the name as the document wrote it | `{"Title": …}` matches `title` in the
reference and not here; pinned in `JSONFieldReadTests` | | A number | `Number` keeps the literal,
and the conversion is a property of the target type (`ParseInt`, `ParseFloat`, overflow), with
`null` setting a map or a slice to zero while leaving a primitive or a string as it was | the tree
keeps the literal as the machine read it and the field read converts it per target, which is what
`int64` and `int` mean there | None; the conversion and the `null` per target are pinned in
`JSONFieldReadTests` | | Depth | `pushParseState` reports `exceeded max depth` at the byte that goes
past 10000 | the same limit, reported as `maxDepthExceeded` | None |

## JSON Feed adapter (stage 3)

**Matching the reference.** Miniflux has no field-read code to port either: the adapter decodes the
document straight into the structs `json.go` declares, so `JSONFieldRead` mirrors what `decode.go`
answers for one field — `d.object`, `d.array` and `literalStore` — over the members the tree keeps.
The order the model fields are written in is `adapter.go`'s: language, URL, title, content, date,
author, enclosures, tags, hash, and each chain stops at the first value it can read, resolve or
parse. Three rules the reference reads as a property of the target type are pinned here: `null` sets
a slice to empty but leaves a string, a bool, an `int64` or a struct field as it started — which is
what a repeated key separates — a number is converted per target (`ParseInt` for the size field), so
a literal that conversion cannot read is reported with the literal as the value, and
`JSONAuthors.UnmarshalJSON` returns without assigning when neither branch can read the value, so a
field keeps what an earlier member gave it. The shape keeps every field the struct declares, not
only the ones the adapter writes, because the type check is what decides whether the document fails
and, for `authors`, whether the leniency keeps the whole array or none of it. Because the field read
walks the members in the order the document wrote them and `saveError` keeps the first failure, the
failure the document reports is the first member the field's type cannot accept, not the first field
the table has.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| The name a field matches | `foldName` also accepts a case-insensitive name, as the reader section
records | not ported: the walk matches the name as the document wrote it | `{"Title": "x"}` matches
`title` in the reference and not here; pinned by `JSONFieldReadTests.nameMatchIsExact` | |
`UnmarshalTypeError` | keeps the value word, the type and the byte offset, and the message is built
from them: `json: cannot unmarshal number into Go value of type string` | the two words are the
case's values — the kind the literal is, and Go's rendering of the field type (`json.JSONFeed`,
`json.JSONAuthor`, `json.JSONHub`, `[]json.JSONItem`, `[]json.JSONAttachment`, `[]string`, `int64`,
`int`, `bool`, `string`) — and the offset is not modelled | None, because nothing in the port reads
the message; the pins name the two words |

## Parser fixture corpus (stage 3)

**Matching the reference.** The 8 parser fixtures are read end to end by `ParserCorpusTests`, which
compares the port against what the reference produces for them. Upstream uses these files only as
benchmark and fuzz inputs, so no upstream test states what a parse produces and nothing could be
ported; the golden files carry the reference's own values, written by running Miniflux v2.3.3 with
Go 1.26 — the version `miniflux/go.mod` pins — over the byte-for-byte copies with the clock fixed to
UTC, through a scratch package inside a verbatim copy of the clone, because the reference's
`internal/` packages cannot be imported from another module. Each golden file says on its own line
that the values below it are the reference's output for that fixture. The method is recorded in
`docs/testing.md`. On the pinned subset the port agrees with the reference on every value, so the
corpus reports no difference; a difference can only enter it by being recorded here.

**What this corpus cannot pin.**

- The zone name a date resolves to, because the reference reads it through the machine's tzdata, the
deviation the date parsing section records. Only the epoch and the offset are pinned, and the port's
fixed zone table can differ from the machine's while those two still agree.
- The double unescape the RSS title chain applies: no title in these fixtures carries a doubly
encoded reference, so entity decoding is pinned through the content instead, and the title rules are
pinned only as far as the bytes show them.
- The date order for the two large fixtures: `published` and `updated` are equal in every entry, so
only the value is pinned, not which of the two the adapter took.
- Relative URL resolution: no fixture has a relative URL, so the URL layer's own tables are where
that is pinned.
- A content value longer than the golden files keep readable is pinned as its first 120 code points
plus its SHA-256. The prefix is taken on the content as read, before the escaping, and the hash is
taken on the whole content, so the whole of it is pinned but not the shape of the middle.

Each golden file names the rule its fixture pins and what that fixture cannot pin.

## Refresh pipeline (stage 4)

**Matching the reference.**

- The pipeline runs `RefreshFeed`'s order (`internal/reader/handler/handler.go` at commit
`c4d54f87`): the user-scoped lookup, the check stamp, the schedule fixed before the request, the
fetch, the `429` reschedule before the failure is reported, then the failure record or the
parse-and-store path. The verified rules are in `docs/reference-notes.md`; the pins read the
reference's values, not this implementation's.

**What differs.**

- The reference opens one transaction per entry, in `RefreshFeedEntries`, and writes the failure
record as its own statement. Rivulet keeps every write of one refresh in a single write transaction,
as the project conventions require, and the failure record is committed inside it before the error
leaves, so the row the reference would write is still stored when the caller sees the error.
- The reference reads `time.Now()` inside `CheckedNow` and `ScheduleNextCheck`. The port reads the
clock through an injected seam, which `docs/plan/stage-4-ingestion.md` asks for; the rule applied to
the value is the same, and the seam is what lets a test pin the stamp.
- The recorded message is a locale string upstream. Rivulet has no locale layer, so the column
carries the typed error's description, and the pins compare the error case, not the wording.
- The reference gates the entry-update branch on `crawler` and `ignore_entry_updates`, columns
Rivulet does not have. With both absent the gate is open on every path, so a known entry is updated
whenever the branch runs; nothing can pin the two flags, because nothing can set them.
- Rivulet's feed row carries a per-feed `check_interval` column, which the reference's `model.Feed`
does not have. Nothing on the refresh path reads it: the reference starts from the configured
minimum on every call, so the pins assert that a stored interval disagreeing with the policy must
not decide the schedule. It is a port-only column, not a place where behavior diverges.
- The feed row's parsed language, the duplicate-feed check, the entry reading time and the user
rules in the reference's processor — filters, rewrite, scraping — are not ported yet; they land with
the later stages. The icon checker is ported, with the call the refresh path makes for a feed, and
the manual refresh path is not.

## Scheduler tick (stage 4)

**Matching the reference.**

- Every rule of the batch builder is the reference's (`internal/storage/batch.go` at commit
`c4d54f87`), pinned one by one because upstream has no test for this builder: strict `next_check_at
< now()`, the error condition appended only for a positive limit, the disabled gate, `ORDER BY
next_check_at ASC`, `LIMIT` only for a positive batch size, the per-host limit applied while the
rows are iterated — after the `LIMIT`, so it caps the rows read, not the jobs kept — and the host as
`urllib.Domain` reads it: the parsed host with its port, no `www.` strip, the string as written when
Go's parse fails. The scheduler calls the builder without a user or a category, so the batch is not
scoped to the user. A failing run does not stop the batch: the reference worker keeps reading the
channel, here the worker keeps pulling from the queue. Each job runs exactly once.

**What differs.**

- The reference logs that a worker received a job and reports a status to the metrics collector
(`internal/worker/worker.go`); it never reports the outcome of the run. RivuletCore has neither
layer, so `tick()` answers with one outcome per job, and the pins compare the typed error case, not
the wording.
- The reference pushes the batch to the channel and does not await it, so a slow batch can overlap
the next tick there; here `tick()` runs the whole batch before it returns. The loop that makes the
two shapes meet lands with `rivulet serve`.
- The pool is workers reading a queue instead of goroutines reading a channel. The toolchain has no
bounded `withTaskGroup` overload, so the window is kept by hand; the cap itself is not pinned —
pinning a cap would need a timed wait, which `docs/testing.md` forbids — and the suite header states
it honestly.
- The due rule compares the instant the caller passes instead of SQL `now()`; this is the injected
clock the pipeline section already records, and the pins read only instants after the process clock,
so the two cannot be confused.
- The weekly entry count, which the entry-frequency mode divides the week by, is a value the policy
is handed here, while the reference reads it inside `ScheduleNextCheck` through the storage layer;
the read itself is pinned by `WeeklyEntryCountTests`, and the pipeline takes it before the fetch, as
the reference does. The reference reads the count only for the entry-frequency mode, and the port
keeps that gate, which is what `docs/reference-notes.md` records.
- The reference writes the count rule with `CEIL`, which this SQLite driver has no equivalent of at
runtime. The port keeps the same value with exact integer arithmetic — (week × (count - 1) + span
  - 1) / span , the ceiling of the reference's real division written as integers. The shape itself
cannot be pinned: an implementation that computes the same rounding a different way answers the same
value for every case here, so what is pinned is the rounding and that the gap keeps its fraction,
which is what the reference's division does.
- A span of 0 with more than one entry makes the reference's division raise in PostgreSQL; SQLite
answers null and `COALESCE` turns it into 0. No case here can pin that, because the reference's half
is a runtime error, not a value.

**What cannot be pinned.**

- `IS false` on the disabled column answers the same as `= 0` here because the column is NOT NULL,
and the order of rows sharing one `next_check_at` is undefined in SQL, so neither can be pinned. The
same is true of the PostgreSQL placeholder style the builder writes, which the port does not
reproduce, and of the ordering clause itself: the pin shows its direction, while a patch that drops
the clause reads the rows through the schema's index on `next_check_at`, in the same order the
clause asks for. The entry-frequency clamps commute for a pair the reference's validator accepts,
and for the pair it would reject the mode's cap is applied again after the delay, so the order of
the two cannot be pinned either. The count read is scoped to the user inside the same write
transaction the refresh uses, and the transaction boundary is what no test here can show.


## Cadence loop (stage 6)

**Matching the reference.**

The reference waits before it reads: `internal/cli/scheduler.go` at commit `c4d54f87` runs `for
range time.Tick(frequency)`, which fires only after the interval, so the first batch read happens
after the first interval and each later read after a firing. The port's loop is that shape: one read
per interval, made against the instant the injected clock gives at that read — the reference's due
rule compares against SQL `now()` at query time, the divergence the scheduler section above records
— and the interval handed to the seam is the interval the loop was built with, which the wiring
gives from `pollingFrequency`. A read that fails is reported and the loop goes on, which is the
reference's `slog.Error` followed by the next firing; here the report carries the failure, because
`RivuletCore` has no logging layer. The pins are `CadenceLoopTests`, which read the calls the loop
makes through the seam.

**What differs.**

The port runs one tick to the end before the next read, which the scheduler section above already
records: the reference pushes the batch to the channel and goes on to the next firing, so a slow
batch can overlap the next tick there.

The reference's scheduler goroutine has no stop rule at all — `time.Tick` is never closed, so it
runs until the process exits — so the seam's answer, whether the loop runs again, is the port's own,
and the pins read only that the loop obeys it.

That a real interval passes is not pinned: the pins read the interval as the value handed to the
seam, because `docs/testing.md` forbids a test that waits, so the real implementation of the seam is
not pinned either and lands with the process-level harness, where the wiring that starts the loop
for `serve` and the signal that asks it to stop are read.

The reference runs a second ticker for the cleanup tasks (`cleanupScheduler`), which this port has
no loop for: retention is pinned as storage rules by `RetentionTests`, and nothing runs it on a
cadence here.

### The serve wiring and the signal path

The wiring is the port's shape: `startDaemon` builds the pool and the scheduler from `config.Opts`
in one place and has no separate piece to read, so `ServeWiring` is what carries the values the
environment names — the interval and the batch size the pins read are the ones `Config.load` parsed
rather than the defaults, pinned by `ServeWiringTests` through test seams that record each call
without waiting.

The shape of the decision matches the reference's `select`: it takes the case that is ready and does
not wait for the other, so in the port the first path to reach the decision answers it and the
answer ends the other one. The signal path answers from the signal as it stands at the instant it
answers, which is the reference's channel read at the firing; the other path answers from the
interval, which is the reference's ticker case. The decision is worded as whether the loop runs
again because the reference's ticker goroutine has no stop rule at all, as the section above
records. SIGHUP, which the reference feeds to a certificate reload, is not ported.

No in-process test reaches the real signal source: the process suite reads the signal path as the
event the child exits on, and the exit code it reads is 0, which is the reference's clean-stop exit
(`internal/cli/daemon.go` at commit `c4d54f87` returns and `main.go` exits 1 only on an error). The
handler is put in place before the server command runs, so a signal arriving while the server starts
answers the wait rather than ending the process on the default disposition — which is what
`signal.Notify` does there, since the process stops on the channel rather than on the signal.

## CLI refresh pass (stage 4)

**Matching the reference.**

- The pass is the reference's manual path (`internal/cli/refresh_feeds.go` at commit `c4d54f87`):
one read of the batch with the values the configuration gives the builder — `BATCH_SIZE`,
`POLLING_PARSING_ERROR_LIMIT`, `POLLING_LIMIT_PER_HOST`, the disabled gate and the due condition —
each job run once through the worker's path with the forced flag false, and the process waits for
the jobs and then exits; there is no loop. The five values are the reference's defaults with its
validators: the three read as a positive number require at least one, while the two switches accept
zero because for them zero is off, and `POLLING_FREQUENCY` is the reference's minute type.
- A job that fails does not stop the rest, which is the worker's rule, and the migrations run when
`RUN_MIGRATIONS` is on, as the reference CLI runs them before dispatching a command.

**What differs.**

- The reference logs the batch, the pool start, each job and the duration through `slog`;
`RivuletCore` has no logging layer, so those lines have nowhere to go here and the pass prints what
it ran to the console, with the wording of that report being the port's own. The reference reports
the size of the whole batch, counting a job it could not refresh, so for a batch with a failure its
number and this report's count of what ran without a failure differ.
- A batch read that fails is logged and the function returns there, which leaves the process exit
code 0; here the error leaves the command and the entry point reports it.
- The reference starts `WORKER_POOL_SIZE` goroutines whatever the batch holds; `Scheduler` here
starts `min(pool size, jobs)`, the shape its own header states, and `SchedulerTickTests` names the
cap as unpinnable.
- The scheduling rule this pass uses is `NextCheckPolicy()` with the reference defaults, so the mode
and the intervals are not read from the environment here (`POLLING_SCHEDULER` and the `SCHEDULER_*`
values), unlike the reference, which reads them through `config.Opts`. Loading those variables is
stage 6 work.
- The reference CLI is a flag (`--refresh-feeds`) on one binary; here it is the `refresh`
subcommand, which is the CLI shape `docs/plan/README.md` chose. The reference also checks that the
schema is up to date, and that check sits on the daemon path — after the migrations and before the
branch that runs the pass, so it covers this pass but not the flags that return earlier. This port
does not port that check, so a pin can only show the flag gates this command.

**What cannot be pinned.**

- That the pass is one pass: no test can show that a loop is absent, and the cadence belongs to the
loop `serve` runs. The pool cap, the closing of the fetcher the command created, and the words of
the console report are the findings the suite header states.


## Status contract (stage 4)

**Matching the reference.**

- There is nothing to match here: the reference has no status command. `internal/cli/cli.go` at
commit `c4d54f87` takes flags rather than subcommands, and none of them reports the feed state: the
closest are `--info` (build information) and `--healthcheck` (a request to an endpoint). The
command, its `--json` document and its console form are the port's own, and
`docs/plan/stage-6-cli.md` keeps the document stable for monitoring and for the stage-4 soak.
- What the document reports is read through the rules the reference does have: the batch builder's
pick answers `due`, and the columns of the `feeds` row answer the rest. The keys mirror the column
names — `id`, `user_id`, `title`, `url`, `site_url`, `fetched_at`, `next_check_at`,
`parsing_error_count`, `parsing_error_message` — because a contract a script compares between two
runs must not rename what it reports. The one key that is not a column is `enabled`, which reports
the `disabled` column as its positive form.

**What differs.**

- An absent stamp is reported as `null` rather than dropped: `JSONEncoder` omits a nil property by
default, so this contract writes the key explicitly, which is what a script reading two runs needs.
- The rows are listed in id order, which the reference never answers for a batch: its builder orders
by `next_check_at`. The counts read every row whatever its state, where the reference's builder
answers only the rows its conditions keep.
- `at_error_limit` is counted only for a positive limit, because for the switch that reads zero as
off there is no filter a row could be at.
- The snapshot is not scoped to a user, as the batch is not. The reference checks that the schema is
up to date on the daemon path, after the migrations and before the branch that runs the refresh
pass, and this port ports neither that check nor any gating beyond `RUN_MIGRATIONS`.
- Without `--json` the same values print as console lines, one per row, and the wording of those
lines is the port's own, so the tests read the values on the line rather than the words.

**What cannot be pinned.**

- That the command fetches nothing and sleeps nothing; which clock it is built with, since a pin can
only read the instant that clock answers; the order of the JSON keys, which a machine-readable
contract does not promise; the wording of the human lines; which number on a human line belongs to
which field, since the pin reads them as a set; and the order a table scan answers without the
ordering clause, which for the rows these pins seed is already the id order. These are the findings
the two suite headers state.

## Icon finder (stage 4)

**Matching the reference.**

- The selector is the reference's four branches (`internal/reader/icon/finder.go` at commit
`c4d54f87`): `link[rel='icon' i][href]`, `link[rel='shortcut icon' i]`, link[rel='icon shortcut' i]
` and `link[rel='apple-touch-icon'][href] `. Only the three `icon branches carry the
case-insensitive flag, every branch compares the whole value, the attribute name is compared
lower-cased, the href must be present and not whitespace-only, and the order is document order. The
document bytes go through the charset layer, which answers unchanged for bytes that are already
valid UTF-8, a value the URL parse cannot read is skipped rather than reported, which is the
reference's warning-and-continue, and each href is written through the URL layer's escaping. The
`data:` rules are the reference's regexp productions and its three encodings, including Go's
`QueryUnescape` for the empty one, which reads a `+` as a space, and Go's `.` production, which does
not match a newline, so a data part containing one is a shape error.
- The join the default icon uses is `internal/urllib/url.go` (`JoinBaseURLAndPath`, which is Go's
`url.JoinPath`) with `path.Join`: the two guards run before the join, the join reads the escaped
path so a percent escape stays as it was read, sequences of slashes are reduced, a `.` element is
dropped, an inner `..` removes the element before it, a `..` that begins a rooted path has nothing
to remove, the trailing slash survives only from the last element, and the base's query stays after
the joined path. The order the search tries is the reference's: the feed's icon URL, the website
document, the root document only when it differs from the website URL, then the default icon joined
to the root, with the first success answering, an earlier failure skipped and the last step's
failure returned. A failing download inside a document moves to the next href, and a `data:` href is
answered without a request, which is the reference's own branch.
- The checker half (`internal/reader/icon/checker.go`) is the guard and the two storage decisions:
the guard reads the mapping for this feed rather than the icon table, and it belongs to the path the
reference runs when the feed is not being forced, so the other path writes and points even for a
feed that already has an icon. The store and the link are two decisions that both run on either
branch: the row is written only when the hash is not stored yet, and the mapping is written after it
on the reuse branch too. The user agent is the value the feed row carries, handed to the builder.
- The refresh path runs the checker only on the branch the reference calls it on: the modified
branch, and the conditional-hit branch does not reach it. The fork the flag selects is the
reference's, and the values the checker is built from are the row's — the site URL with the empty
site fallback, the user agent — plus the icon URL the parse produced, which is the value
`RefreshFeed` puts on the model it read before it builds the checker. The call is written where the
reference has it, after the entry loop and before the fetch state is written; that position is what
no pin can show, so it is recorded here rather than pinned, and the fallback is pinned by
`RefreshPipelineTests` rather than by the icon suite. **What differs.**

- The selection walks tokens, not a document tree. For the cases the suite reads the answer is the
same, because the tokenizer lower-cases attribute names and reads a raw-text element's content as
data, so a `link` inside `title` is text rather than an element. What no test can show is the
selector's test that the `href` attribute exists at all: a missing attribute reads as the empty
value on this path, so the pins assert the value is not empty, not that the attribute was there. The
same is true of the tree's insertion modes the reference has and this port does not — the pin that
reads `/>` asserts the token kind, not what the reference's tree does with the flag, which is not
acknowledged outside foreign content and has nothing to do for a void element.
- The reference hashes the icon with `crypto.HashFromBytes`, which is `hash/fnv` FNV-128a; this port
uses SHA-256, the function it already has for the entry identity, so the stored hash value for the
same bytes differs from the reference's. The pins can fail on which bytes the checksum is taken
over, and cannot fail on which checksum function is used. No Go toolchain on this machine, so the
reference's values cannot be produced here; the closure is deferred to `Tools/parity` (stage 7).
- Go's base64 decoder accepts a value whose last quantum is not padded — two or three characters
left — while Swift's `Data(base64Encoded:)` refuses it, so such a value is an error here. Go also
skips CR and LF inside the value, which cannot reach this path: the tokenizer turns a CR in an
attribute value into a LF, and the `.` production the port reproduces excludes LF, so the decoder
never sees either. No case here reads the unpadded case, so the difference is recorded rather than
pinned.
- The reference reports these failures as messages and logs each step of the discovery. RivuletCore
has no logging layer, so the data-URL failures are typed cases and the pins compare the case, not
the wording.
- The reference reports the empty body through `LocalizedError`, which both paths read, measured as
`Content-Length` and exempting the conditional hit; `ReadBody` reports an empty buffer for any
response, so an icon fails on a `304` where the document path does not. This port has one rule for
both paths through `FetchResponse.error()` and restates the icon path's half in `IconDownload`,
which is the half the pins can fail on. The measurement basis is the difference: a chunked response
with an empty body is a failure here and not there, which no case here reads, so it is recorded
rather than pinned.
- The orphan pass reports the number of rows it deleted. The reference reads `RowsAffected` from the
statement result; this SQLKit version gives no row count for a raw statement, so the port reads
`SELECT changes()` from the same connection immediately after the statement, which is the same value
for one statement on one connection.
- The mapping from a feed to its icon is the feed row's `icon_id` here, where the reference keeps a
`feed_icons` table (many-to-many, `internal/database/migrations.go`). The replace and the orphan
pass read the same decision; the pins cannot fail on the join table itself, which this port does not
have.
- The join does not escape what it joins, which is Go's documented expectation that the elements are
already escaped. A character the path mode escapes is written as its escape when the URL is
rendered, so a joined element carrying a space becomes `%20`; that escaping is the URL layer's rule,
pinned by its own suite, not the join's.
- The port's `icons` table carries `created_at`, which the reference's does not have, so the port
writes the instant itself; nothing in the icon path reads it, so no pin can show it.
- The guard the icon path reads lower-cases the scheme, where `IsAbsoluteURL` compares the prefix as
it was read, so `HTTPS://` is refused upstream and accepted here; the reference's builder checks
nothing and fails at the client with a different class, so the guard is the port's own rule,
recorded in `docs/reference-notes.md`.
- The checker half (`internal/reader/icon/checker.go`) reads the mapping through `HasFeedIcon`,
which answers `false` when its scan reports nothing because it does not look at the error the scan
gives it; this port answers `false` the same way for a read that reports nothing, and for a feed
with no row at all, so the pins cannot tell a failing read from an empty one.
- The reference's storage calls each open their own transaction, so the icon row and the mapping
commit apart from the entry batch. Rivulet runs the checker inside the refresh's single write
transaction, so the three writes commit together, which no pin can separate: the pins read what the
commit left, not the order the statements ran in. The reference also has no `feeds.icon_url` column,
so the icon URL the parse produced reaches only the checker and nothing is stored for it; this port
has the same shape — the mapping is stored, the URL is not.
- The reference logs each checker failure and continues. This port has no logging layer, so a
failure ends inside the checker without a record: the pins can read only that the call completes and
nothing was written.
- The checker hands the builder the user agent as the value the feed row carries, which is the
`WithUserAgent` precedence the port's builder already implements. The reference reads the value from
the feed model and the port takes it as an argument, so the pin can fail only on the checker handing
it on, not on which value wins when it is empty.
- Image resizing is not ported, because decoding an image needs a dependency that has not been
approved. The reference decodes the icon, rejects one whose side exceeds 4096 or whose pixel count
exceeds 4096×4096, and leaves an icon at or under 32×32 as it is; this port stores the bytes the
encoding branch produced. The SVG minifier upstream is not ported either, so the stored content is
the value as read. The reference's checker has a branch for an answer with no icon and no error,
which is that rejection; this port has no case that answers without an icon, so the branch has
nothing to pin.

## User rules and password hashing (stage 5)

**Matching the reference.**

- The order the creation rules are read in is the reference's, and `UserValidationTests` pins it
with an input that would fail two rules naming the rule it reaches first; the character class read
per Unicode scalar and the password minimum counted as bytes are pinned by their own cases.
- The command's own order is the reference's too: the existence read runs before any rule, so a
stored name is skipped whatever its characters are. The pin seeds a name the character class
rejects, and only the skip path can end that run without a failure, so the run completing is what
shows the order. The trim and the secure read are `askCredentials`'s, and `TestConsole` records the
flag of each read, which is what lets a pin name which path the read took rather than only the value
that came back.
- The 72-byte rule is the reference's on the hash path, and the port keeps it there. On the compare
path the port answers as the reference does, which has no length check there: its comparison reads
at most the first 72 key bytes, so a 73-byte plaintext that shares those bytes with the stored
password answers as a match. Vapor's C implementation truncates the plaintext the same way, so the
pin names the reference's answer rather than a rule the port added.
- The cost is passed explicitly as 10, because Vapor's `hash` defaults to 12 while the reference's
is 10 at the version `go.mod` pins.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| Revision marker | writes hashes as `$2a$` | writes `$2b$` | The same algorithm at the same cost. A hash written at the reference's marker verifies through this port, which is what `BcryptHasherTests` pins; which marker this port writes, and whether its hashes read back through the reference, is not pinned, so a stored hash from either is readable here |
| Rule identity | four localized error names resolved through the locale catalog | the rule as a named case, and the sentence a command prints for it is the port's own | The text differs; which rule an input fails on is the same, and that is what is pinned. The reference's names are recorded in `docs/reference-notes.md` |
| Report wording | two `slog` records with fixed sentences, sent to the log | console lines, with the port's own wording | Pins read the outcome and the name carried on the line, not the sentence |
| Interactive-terminal check | refuses to read when the input is not a terminal | not ported, because this port reads through the console seam and a captured console has no terminal to test | A non-terminal input is accepted here. No pin can reach this case, so it is stated in the command comment |
| Environment path | `ADMIN_USERNAME` and `ADMIN_PASSWORD` with `CREATE_ADMIN` create the account on the daemon branch | not ported with this slice, because that path belongs to `serve` | The console path is pinned; the environment path is named in the stage plan and arrives with stage 6 |
| Transaction boundary | `CreateUser` writes the row and the default "All" category in one transaction | two statements, with the transaction left to the caller, because a repository must not open a nested connection | No pin can separate the two statements; the pair is asserted as what the run left behind, which is stated in the repository comment |

## Integration credentials (stage 5)

**Matching the reference.**

- The Fever `api_key` is the reference's derivation, read as its output: the pair joined with a
colon, hashed as its UTF-8 bytes, written as lowercase hex, with the parts joined as read. The pins
compare the values the reference produced at the toolchain `go.mod` pins, so the choice of digest is
read as the reference's fact rather than as behavior the port reproduced.
- The order the two duplicate checks are read in is the reference's, and
`IntegrationValidationTests` pins it with an input that would fail both rules, naming the rule the
reference reaches first. The guard that an empty name is not checked is pinned inside the rule
function; the guard that keeps the storage read from happening for an empty name is the command's,
and no pin can fail on it, because the pins hand the storage answers in as values, so the code
states it and the suite header names it as not pinned.
- Both checks exclude the row they belong to, compare the value as read with no `LOWER`, and read
their own column; that is upstream's `user_id != $1`, and `UserRepositoryTests` pins each of the
three.
- A blank password read leaves the stored value as it was, which is what the reference does for its
two password fields, and the integration names are stored as given, without the lowercase the
account name gets. The password itself is stored on neither side: the reference's form field feeds
the derivation, and the column that once held it is dropped by `migrations.go:413`.
- The reference reads each duplicate check and then derives that pair's value, in the order its form
fields are handled; this port reads both checks before deriving anything, which cannot change the
outcome because a hit writes nothing.
- The two reads the client auth path is built on are pinned by `ClientAuthTests`: the Fever lookup
compares both sides lowercase, which is upstream's `lower(integrations.fever_token)=lower($1)`, and
the Google Reader read compares the name as read, with no `LOWER`, which is upstream's
`googlereader_username=$1`. For "no row" the Fever read answers `nil`, which is what upstream does
too, and the account-name lookup lowercases what it is given, which is upstream's
`username=LOWER($1)`, so the Google read and that lookup answer one input differently — that
difference is what the control pin shows.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| Where the values live | a separate `integrations` table keyed by `user_id`, with an `*_enabled` flag per integration | the credential columns of `users`, and no flag: a credential is present or it is not | The flag is not ported, so the reference's branch that clears a pair when its flag is off has nothing to pin here |
| A blank name field | writes what was submitted, so a blank field clears the stored name | keeps what the row already holds, because a command line reads blank as "not given" | A blank name behaves differently: the duplicate check sees the kept name here where upstream's guard would skip an empty field, and the value derived from the pair is the digest of the kept name rather than of an empty part. The pins read the keep rule, and the difference is stated in the command comment |
| Whitespace around a read | the form writes what the request submitted, untrimmed | the console read trims the line before the value is used | A read with spaces around it behaves differently here; the pins read the trim |
| Unique index | none on `fever_username`, `googlereader_username` or `fever_token` | `fever_token` carries `UNIQUE` from stage 0's schema | Two accounts with the same token are refused here and accepted upstream; the rule is the schema, so no patch can reach it and it is not pinned |
| A row that stores nothing | the integration row is created for every user and its `fever_token` and `googlereader_username` columns are `text default ''`, so an empty input matches the stored empty value | the columns are nullable, so nothing stored is `NULL` and an empty input matches nothing | A blank input can find an account upstream and finds none here; the pin reads the port's side, so upstream's side has nothing to pin here |
| The answer for "no row" | `UserByFeverToken` answers nil, while `GoogleReaderUserCheckPassword` reports "unable to find this user" as an error, and errors again when the stored value is not a hash | `nil` for both reads | Only the Google half differs, and the pins show the answer rather than the wording, so the wording is stated in the code comment |
| Path to the values | the web form handler, with a session flash and a redirect | the CLI, reading through the console seam with the port's own wording | Only the outcome and the stored values are pinned, not the sentences |
| Which account is written | the user of the web session | the name read from the console, which must have a row | A name with no row ends the run here; upstream cannot reach that case |
| `updated_at` | the `integrations` table has no such column | stamped on the write, because the `users` row carries it | A stamp no pin can read, so it is stated in the repository comment |

## Google Reader auth path (stage 5)

**Matching the reference.**

- The JSON this path writes is `json.Marshal`, not the platform encoder: the compact form with no
spaces, the object keys in the order the document declares them, and the solidus written as it is.
Swift's own encoder is compact too, but its key order is the dictionary's, which is not the order
the document declares them in, and it escapes the solidus and leaves the three HTML-sensitive
characters as they are, so the port writes the document with Go's escape classes: the quote and the
backslash, the three control characters with their short forms, every other character below U+0020
as `\u00XX`, the three HTML-sensitive characters and the two line separators as `\uXXXX` with
lowercase digits. `JSONValueTests` pins each class against the reference's output at the toolchain
`go.mod` pins, and the key order with a document where the two orders differ.

- The response builder writes `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY` and
`Referrer-Policy: no-referrer` on every response of this path, so each shape it writes carries them,
including both 401 answers; `GoogleReaderAuthTests` pins the three headers on each of the six
responses this piece answers. The builder's `Vary: Accept-Encoding` appears only above its
compression threshold, which none of these bodies reach, so nothing here can pin it.

- `Content-Type` is what the reference sets on this path — `application/json` with no charset, and
`text/plain; charset=utf-8` for the text shapes — written explicitly, because Vapor's default adds
the charset to the JSON one.

- The form read is Go's `ParseForm`: the urlencoded body pairs are read into `r.Form` before the
query pairs, so the value `Form.Get` answers for a name both sides carry is the body one. A pair
with no `=` is a name with an empty value, empty pairs are skipped, `+` is a space while `%2B` is
the character, `;` is not a pair separator, and the error is reported for one pair — a pair that
carries a `;` anywhere, or whose name or value cannot be unescaped, is skipped and the read
continues with the pairs after it — so `ParseForm` answers both that error and what it read, and the
handler answers the error before reading any value; `r.URL.Query()` discards the error and keeps
what parsed, which is what `GoogleReaderQuery` is, and `GoogleReaderQueryTests` pins which pairs
answer. A multipart body is never part of the form. The media type is read with its parameters
ignored and compared lowercased, as Go's `mime.ParseMediaType` reads a type with its parameters
dropped, which the pins read with a charset parameter and with the type written in upper case. The
plan's earlier note had the query first; Go puts the body first, so that note is corrected here.

- The header is read as Go's `strings.Fields` splits it, which collapses the whitespace between the
fields: exactly two fields, the second split on exactly one `=` with the empty part kept, so a value
that carries another equals sign is not the shape the reference reads.

- The two 401 answers are the reference's two: the login path answers the JSON document without the
bad-token header, the protected path answers the text shape with it.

- The contract rules the routers read are ported as the reference answers them, and the three places
where a Swift reading would have differed are read as Go reads them: the hex scan skips the space
before the field and reports `unexpected newline` where a newline is what it runs into, because a
newline is not one of the characters that skip takes; the scan works per Unicode scalar, so a base
character with a combining mark is the base character; the trim is Go's `unicode.IsSpace`, not this
port's `.whitespaces`, which does not have the control forms; and the escape reads its two
characters only after checking that both are there, so a `%` that runs off the end of the pair is
the error rather than a read past the end. `GoogleReaderItemIDTests` and `GoogleReaderQueryTests`
pin each of these, and the values are in `docs/reference-notes.md`.

- The catch-all answer is pinned on both halves the reference registers: the exact path and the
subpath, which RoutingKit matches with the lowest precedence, so a path an exact pattern registers
wins for the method that pattern names. The no-slash path is pinned as the divergence below.

- What the handlers choose — which endpoints apply the output check, which status each error answer
writes, and the two ways the stream branches read the same exclude name — is pinned by
`GoogleReaderHandlerTests`, and the rules are listed in `docs/reference-notes.md`.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| JSON write | `encoding/json` | the same rules, written by `JSONValue`, because the platform encoder writes its dictionary order (sorted on Darwin), escapes the solidus and leaves the HTML class as it is | No observable difference; the port has its own writer because the platform one cannot reproduce the reference's bytes, and the pins read that writer |
| Error wording | `strconv.ParseInt` names the token with `%q`, so a control character inside it is written escaped, as `parsing "\t12345"`, while the input part of the sentence is written raw | the token is written as it is, so a control character inside it appears raw | The words are the same; only a value that carries a control character is written differently, and the pins read values that have none |
| The escape wording | `fmt.Errorf("invalid URL escape %q", named)` quotes the text it names, so a control character inside it is written escaped, as `invalid URL escape "%\ta"` | the text the read names is written between plain quotes, so the same input answers `invalid URL escape "` with the control character raw, and a multi-byte character is cut as a whole character here where Go cuts three bytes | The words are the same; only a named escape that carries a control character or a multi-byte character is written differently, and the pins read escapes whose characters are ASCII |
| Bytes that are not valid UTF-8 | a string holding an invalid byte is written as `\ufffd`, and a form value can hold one because Go's `unescape` returns raw bytes | a writer cannot receive an invalid byte, because a Swift `String` holds valid UTF-8, but the form read can build one: a percent escape whose bytes are not valid UTF-8 answers U+FFFD here, where Go keeps the byte | Only the reference has the write case; the pins read what this port writes for a valid replacement character, and the form half is recorded in the code comment |
| The compare | `crypto/subtle.ConstantTimeCompare` | the same form, one pass over the bytes | No pin can read the timing, so the answer is pinned, including that the value is compared whole rather than as a prefix |
| Path matching | the catch-all pattern is Go's subtree pattern, so it answers for any path under `/reader/api/0/` | the same, as RoutingKit's catch-all, which has the lowest precedence, so a path an exact pattern registers wins for the method that pattern names | No observable difference for the paths this port registers; the method mismatch below is where the two still differ |
| No trailing slash | 307 with `text/html; charset=utf-8` and `<a href="/reader/api/0/">Temporary Redirect</a>.\n\n`, written before the auth middleware, so an unauthenticated request gets the redirect rather than 401 | the route is matched on the path segments, so the path without the trailing slash reaches the same handler and answers the catch-all `[]` + 200, or the protected 401 when it has no token | `GoogleReaderAuthTests` pins this port's answer for both halves; the reference's redirect is recorded in `docs/reference-notes.md` |
| A method the pattern does not register | 405 `Method Not Allowed` as `text/plain; charset=utf-8`, also before the auth middleware | 404, which is what Vapor's router answers for a path it has no pattern for | The same for an unauthenticated request: upstream answers 405 where this port answers 404 |
| Two rows and the last-login stamp | the integration row and the user row read by id, and `SetLastLogin` on a successful compare | one row, and no last-login column | The same single row here; no pin can read the stamp, so the suite header names it |
| The message for the category rules | the locale string the rule key translates to, as `error.category_already_exists` → "This category already exists." | the rule name, so the handler answers `alreadyExists` | A client that compares the body text sees a different string; the rule is pinned as pure logic and the keys are recorded in `docs/reference-notes.md` |
| The rename statement | `UpdateCategory` writes `hide_globally`, which this port's schema does not have, and does not stamp `updated_at` | the title only, and `updated_at` is stamped on every mutation, as the port's schema rule states | No observable difference for what the port has; the stamp is the port's own convention, so no pin reads the reference's side |
| The part below a second | `before` is a `time.Time`, so a microsecond value keeps its sub-second part and an entry published at that part is marked | the entry column holds whole seconds, so the answer is the whole part of the value | `GoogleReaderTimestampTests` pins the port's side — cut to whole seconds rather than rounded — and the reference's side has nothing to pin here |
| The media proxy | `RewriteDocumentWithAbsoluteProxyURL` rewrites the document's media links and `ProxifyEnclosureURL` rewrites the attachment urls, by the configured mode and resource types, with the hmac of the private key as the path segment | no proxy, so the stored content and the attachment urls are written as they are | With the reference's default mode `http-only` an https value is unchanged anyway, so the pins read the stored values; an http resource, the `all` mode and a custom proxy url are where the two answers differ |

## CLI feed commands (stage 6)

The reference's CLI dispatches by flags on the executable (`-create-admin`, `-refresh-feeds`,
`-export-feeds`, `-info`, `-health-check`) and reaches the feed rows through its web UI, so the
command set below is the port's own surface: what is traced to the reference is the rule each
command applies and the storage rule it reads, not the shape of the command line. The pins are
`FeedCommandTests`, `FeedManagementReadsTests` and `FeedValidationTests`, and for the listings
`ListingCommandTests` with the two reads pinned by `CategoryRepositoryTests` and
`UserRepositoryTests`.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| The command set | no `add`, `remove` or `list`; the feed rows are managed through the web UI, and the CLI has one flag per operation | `add <url> --user <name> --category <title>`, `remove <url> --user <name>`, `list --user <name>`, `list --categories`, `list --users` | Nothing upstream is contradicted: the surface is the port's own, and only the rules the commands apply are traced to the reference |
| Which account a command works for | the session or the login, so a command line has no account to choose | the account named by `--user`, read as the account lookup reads a name, and the single account when none is named; naming none with several accounts is the port's rule | No reference behavior to compare; the rule is pinned by its name, and the wording a failing run prints is the port's own |
|| The account read from the environment | the CLI reads the environment through
`config.ParseEnvironmentVariables()`, and the only account name it reads from there is
`ADMIN_USERNAME` for `create-admin`; `export-user-feeds` takes the username as the value of its own
flag | no environment flag is ported: the account is the one `--user` names, or the single account
when none is named | Nothing upstream is contradicted and there is no read to mirror; the
`LIST_USER` and `ADD_USER` names the earlier plan imagined are not ported, so nothing the pins read
changes |
| A named account with no row, and a url the account has no row for | the request path reads the account before the rules and reports a database failure | the port reports `accountNotFound` and `feedNotFound`, because a command line that writes or deletes nothing has to say so | The reference has no rule for these; the port names them and pins them by name |
| The message a rule answers with | the locale string the key translates to | the rule name, as the write handlers of this port already write it | A terminal or a script reading the text sees a different string; the rules are pinned as pure logic and the keys are recorded in `docs/reference-notes.md` |
| The url written to the row | the create path writes `feed_url` as submitted; the discovery path cleans the value before writing it | the command writes what it read, because `add` is the insert only and does not discover | The two answers are the same for a url with nothing to clean; a tracked parameter is where a discovery path would differ |
| The listing order | `parsing_error_count DESC` with `lower(f.title) ASC` appended after the sort expressions, and only when there is at least one | the same rule, read by the storage layer | `lower()` on PostgreSQL folds non-ASCII letters; SQLite's `LOWER` folds ASCII only, so a title with a letter outside ASCII is where the two answers differ — no pin reads one |
| Which listing a run answers | no listing command at all; the read this port mirrors, `Categories`, is what `tag/list`, `GET /v1/categories` without counts and the feed pages use, and `Users` orders by username; the reference's own category page reads `CategoriesWithFeedCount` with the user's `categories_sorting_order`, whose column default is `unread_count` | one listing per run: `--categories` names the title read, `--users` names the username read, and no flag means the feeds | Nothing upstream is contradicted: the flags are the port's own shape, because `@Argument` has no default, so a run cannot name an optional listing, and the pair of flags is the port's rule `multipleListings`; only the two orders are traced to the reference |
| Which account a listing applies to | `Categories` filters by the user; `Users` has no account condition | the same: the account the run resolves applies to the categories, and the account listing prints every row | Nothing upstream is contradicted; the read the pin compares is the pair of titles on two accounts |
| The order the two listing reads answer in | `ORDER BY title ASC` and `ORDER BY username ASC`, which Postgres answers with its collation | the same two reads, which answer in the byte order | The collation cannot be ported, so `Zebra` before `apple` is where the two answers part; the pins read the port's byte order, and this row is the record of the difference |
| The `position` column | the reference's `categories` table has no `position` at all: `id`, `user_id`, `title`, `hide_globally` | this port's schema has `position INTEGER NOT NULL DEFAULT 0`, and the listing prints the value the row holds | `position` and the position-then-title order `CategoryRepository.list` reads by it are the port's own; the listing here reads the title read, which is the reference's order, so the pin can fail only on the value the row holds |

## Maintenance commands (stage 6)

The reference has no `backup` and no vacuum: its CLI dispatches by flags and the word `vacuum` does
not appear anywhere in its sources, so the whole surface below is the port's own. Only what SQLite
enforces on the destination is shared. The pins are `MaintenanceCommandTests` for the runs and
`MaintenanceTests` for the storage rules they call.

**Known differences.**

| Case | Reference | Rivulet | Impact |
| --- | --- | --- | --- |
| The command set | no `backup` and no vacuum; the executable takes one flag per operation | `rivulet backup <destination>` and `rivulet vacuum` as commands | Nothing upstream is contradicted: the surface is the port's own, and only the rules SQLite reads are shared |
| The destination | nothing to compare | the path as the command read it, so a relative value is the process's working directory rather than the data directory; the port does not build a missing parent directory and does not overwrite a file it did not create | The port's choice, so the pins read the filesystem after the run; a run that wrote nothing reports it, which is also the port's rule, and the wording is the port's own |
|| Overwriting what the destination holds | nothing to compare: the reference has no backup command,
and its CLI takes one flag per operation with none for replacing a file | `--force` names a
destination the run may replace, so the file the path names is removed and the snapshot at the run
is written in its place, read as the filesystem reads the path rather than as a database the run can
open, while a path that is a directory is reported rather than deleted; without the flag the
destination is refused and left as it was | The port's own rule, pinned by `BackupForceTests`. The
flag does not skip the room check, and a run that cannot hold the copy removes nothing, so the pins
read the check as running before the replacement |
| What the copy holds | nothing to compare | the snapshot at the run — the content the source had when the run read it, compacted — in a file of its own that does not change with the source afterwards | A byte copy of the main file would answer a copy without what the WAL holds; the pins read the copy through a second driver |
| The rebuild | nothing to compare | the file shrunk and every row kept, then the truncating checkpoint the stage-1 wrapper ends with | No reference behavior to compare; the checkpoint is pinned as a storage rule and not as a command rule, because `RivuletApplication.shutdown()` runs one after every command |
| The room the copy needs | nothing to compare: the reference has no free-space check, and its CLI has no backup command to check for | the estimate is the bytes the source holds as the filesystem reads them — the main file plus the `-wal` beside it as the filesystem reads it — times the factor 2 `docs/plan/stage-1-storage.md` documents for `VACUUM INTO`; the room is read at the directory the destination is in, which is the current directory for a destination named as a bare name, and the comparison is strictly less, so a destination with exactly the estimate holds the copy; a room the filesystem cannot read answers a refusal, and a size it cannot read counts as nothing | The port's own rule, read at the start of the `backup` run before anything is written, so a run that cannot hold the copy writes nothing; `vacuum` is not checked, because it rebuilds the file it already holds rather than writing a copy beside it |
