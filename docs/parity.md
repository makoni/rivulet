# Parity notes

Where Rivulet differs from Miniflux, and why. Reference-verified behavior itself lives in
[reference-notes.md](reference-notes.md); this file records the places where the port knowingly
diverges — because a platform facility behaves differently, or because the reference does
something we choose not to copy. Stage 7 consolidates and re-checks these notes.

## Charset decoding (stage 3)

**Matching the reference.**

- The WHATWG label table is transcribed from `golang.org/x/text` v0.40.0 `encoding/htmlindex`
  (BSD-3-Clause, attributed in `NOTICE`) — the same data the reference resolves labels against,
  including the aliases the IANA registry gets wrong (`iso-8859-1` → windows-1252,
  `gb2312` → GBK, `utf-16` → little-endian, `iso-2022-kr` and `hz-gb-2312` → replacement).
- A document that is already valid UTF-8 is never converted, whatever label it declares; a wrong
  prolog cannot double-encode it. An unknown label is only an error when the bytes are not valid
  UTF-8.
- Detection follows the reference order: BOM → content-type `charset` → `<meta>` prescan over the
  first 1024 bytes → "looks like UTF-8" heuristic → `windows-1252` default. A `utf-16` `<meta>`
  and the heuristic leave the bytes as they are, because the reference uses `encoding.Nop` there.
- The UTF-8 path replaces each maximal subpart of an ill-formed subsequence with one U+FFFD, the
  way `x/text`'s `utf8Decoder` does. This is what makes the output always valid UTF-8, and the
  tests pin the boundaries of the W3C error table (overlong forms, surrogates, forms above
  U+10FFFF, sequences cut off by the end of the document).
- Undefined positions of single-byte encodings become U+FFFD, like the reference decoders; the
  test pins the windows-1252 positions (`81`, `8D`).
- A UTF-16 byte-order mark is kept in the output as U+FEFF, matching the reference's
  `IgnoreBOM` decoder policy.
- `x-user-defined` (high bytes → U+F780–U+F7FF) and the replacement encoding (one U+FFFD) are
  implemented directly.
- `hasUTF8XMLDeclaration` compares the declared value with `utf-8` ASCII-only, as the reference's
  `bytes.EqualFold` does, so the valid alias `utf8` is not recognized there.

**Known differences.**

| Case | Reference (`x/text`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Big5 byte `80` | U+FFFD | U+0080 (ICU/Foundation) | A private byte survives where the reference drops it |
| Big5 byte `FF` | U+FFFD | U+F8F8 (ICU private use) | An invalid byte becomes a PUA character instead of U+FFFD |
| Invalid sequences in GBK/GB18030/Big5/Shift_JIS/EUC-KR/ISO-2022-JP | U+FFFD per maximal subpart, which can cover several bytes | platform decoder, then glibc `iconv` (which reports one error per stop), then the UTF-8 replacement rule when the platform has no converter | Corrupt spans can differ in the number and placement of U+FFFD; valid text is unaffected |
| EUC-JP on Linux | decoded by `x/text` | Foundation returns `nil` for every input, so the glibc `iconv` fallback decodes it | Same result for valid documents; pinned by a test |
| Single-byte tables | `x/text` `charmap`, so `iso-8859-8-i` keeps its own visual table and `iso-8859-6` its own | CoreFoundation resolves the IANA name, which can map an alias to a different table (for example `iso-8859-8-i`) | Only exotic input differs; no fixture covers it |
| `<meta>` prescan | full HTML tokenizer, with character references unescaped in attribute values and the vertical tab as whitespace | tag scanner (comments, quoting, attribute order, 1024-byte window) | Malformed markup the tokenizer recovers from can end the scan; a label written as an entity is not resolved |
| Content-type `charset` parameter | `mime.ParseMediaType` | direct parameter scan | Some malformed headers yield a charset where the reference falls through to detection |

None of these differences is observable on the ported fixture corpus: all fixture assertions the
reference makes are reproduced. Valid documents in a legacy encoding decode identically.

## XML reader (stage 3)

**Matching the reference.** The buffer rules, `space`, `attrval`, `text`, the comment, CDATA and
directive reading, `getc` and `mustgetc`, the namespace scope and the end-of-root rule follow
`encoding/xml` (Go 1.22) line by line, with the configuration Miniflux builds (`Strict = false`,
`Entity = xml.HTMLEntity`). `ungetc` is an equivalence rather than the same function, since the
reference never reads after a failure. The name classes are the one approximation, recorded in the
table below. The entity table is transcribed from it and attributed in `NOTICE`.

**Known differences.**

| Case | Reference (`encoding/xml`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Name classes | two explicit `unicode.RangeTable`s (`first`, `second`), a transcription of an older Unicode version | Swift Unicode properties: letter, number and grapheme-extend, plus the ASCII name bytes and `-`, `.`, `·` | Go's tables omit letters Swift reports as letters (`ª`, `µ`, `º`, the ligature and digraph forms) and most characters above the BMP, so Rivulet accepts names the reference rejects. No fixture covers it |
| `text` rejects invalid UTF-8 | reports `invalid UTF-8` for a rune it cannot decode | not modeled: invalid sequences are removed before the document is read, so the check is reached only when the label is never resolved, which is the case in the next row | The reference fails such a document, Rivulet filters it; pinned by a test |
| Label | `procInst` is applied to an instruction token, so the label is the one carried by the first instruction whose target is `xml`; Miniflux decides the path from the first `encoding=` of the whole document, which is not the same lookup | the same, with the two lookups kept apart: the path is decided by the first `encoding=` anywhere, the label is read from the first instruction with the target `xml` | A body `encoding=` decides the path but is never resolved, so such a document fails in the reference and is filtered here; pinned by a test |
| Instruction start | `procInst` is reached at a token boundary, so a `<?` inside a comment, a CDATA section or a quoted attribute value is not an instruction | the label scan reads `<?` occurrences in the bytes, so one inside markup counts | A Latin-1 document whose only `encoding=` is inside a comment converts here and fails in the reference; pinned by a test |
| Where the conversion applies | `switchToReader` converts from the instruction on, so bytes read before it are not converted | the label is applied to the whole document | Bytes before a late `xml` instruction that are not valid UTF-8 fail in the reference and are decoded here; pinned by a test |
| End of document inside a name or an unquoted value | fails, because `mustgetc` cannot read past the end | fails as `unexpectedEOF` | Same result; the difference is only in the message, which is not modeled |
| Error reporting | `SyntaxError` with a line number and a message | typed `XMLError` cases, no line numbers | Callers match on the case, not on the text |
| Bare `io.EOF` | returned as it is when the stack is empty, such as after a comment at the top level, or when it is at the record `pushEOF` put; `Token` converts it otherwise, and `mustgetc` converts it on every read that finds it | the same `unexpectedEOF` case, because the port keeps one failure | Only the message differs; the reader reports it as one failure |
| `translate`'s `DefaultSpace` | falls back to the decoder's `DefaultSpace` for a name with no prefix | not ported, because the reference never sets it, so the fallback assigns the empty string | None |
| `AutoClose` | a list the reference can be given, which invents end tags for unclosed elements | not ported, because the reference never sets it | None |
| `pushEOF` and `popEOF` | used by `unmarshalInterface`, so only for values whose type implements `UnmarshalXML`; Miniflux implements it for two types (`internal/reader/rss/rss.go:210`, `internal/reader/opml/opml.go:75`) | not ported, because this layer reads tokens and not values; the marker marks where `unmarshal` stops for a value read as a plain struct | The reference fails a value implementing `UnmarshalXML` that stops before its end tag (Go's `read.go:218-220`); nothing here checks that, because there is no value layer |

## Date parsing (stage 3)

**Matching the reference.**

- The layout catalog is transcribed verbatim: the three constants of the local-time group, then the
  206 layouts in the order the reference tries them, with the entries it repeats left repeated. The
  79 normalization pairs are transcribed in order, matched at a position by the priority Go gives
  them, which is the order the pairs are listed in. The only pair whose pattern is a prefix of
  another is `Mai`, and the longer `Mai ` is listed before it, with the same trailing space in its
  replacement, so the two rules give the same output for every input, and the scan advances by the
  pattern length rather than by the replacement.
- The reading primitives (`skip`, `getnum`, `getnum3`, `lookup`, `atoi`, `parseTimeZone`,
  `parseGMT`, `parseSignedOffset`, `parseNanoseconds`) follow Go 1.22 `time/format.go` line by
  line, over UTF-8 bytes: a layout space matches a run of spaces, `lookup` is a case-insensitive
  ASCII prefix match, and a fractional kind keeps only the digit count because `parseNanoseconds`
  accepts `.` or `,` whichever the layout writes. `atoi` accepts a leading sign, which is what lets
  the two-character year read `+6` and an exact fractional run read `.+5`, while `getnum` does not,
  so the offset fields take digits only; `parseNanoseconds` reports a negative result as out of
  range.
- The zone resolution keeps Go's sentinel: `zoneOffset` starts at −1 to mean "no offset was read",
  so a value of exactly −1 second is read as no offset at all, and the zone falls back to the
  default location, which is UTC in both.
- A value that reads no zone is read as UTC, which is what the reference does too: `time.Parse` is
  `parse(layout, value, UTC, Local)`, so its default location is UTC, and `parseLocalTimeDates` pins
  UTC for its three layouts as well. The machine's zone is consulted only when a name or an offset
  was read, which is the fixed table below.
- Go's `RFC3339` fast path is not ported, and that changes nothing at all: `Parse` falls back to the
  general `parse` when `parseRFC3339` fails, so an unpadded field is accepted either way, and for a
  value the fast path accepts the result is the same as the general path's, location included. The
  only place where the port and the reference can differ for such a value is the fixed zone table.
- Field ranges are the reference's: 0–23 for the twenty-four-hour pattern and 0–12 for the
  twelve-hour ones, since twelve is noon or midnight; minutes and seconds below 60; the day
  validated against the month; the year-day 1–365 with the leap-year decrement; and the two-digit
  year split at 69.
- Day counting is Go's proleptic Gregorian `Date`, checked against `daysBefore`, `daysIn` and
  `daysSinceEpoch` for every date in years 0 through 9999, which is the range the four-digit pattern
  reads; a layout with no date leaves year 0 behind, and a `Calendar` is not involved. The suite
  pins the leap-year and year-day cases rather than the whole range.
- `checkTimezoneRange` belongs to the entry point, not to the engine: an offset outside −12:00 to
  +14:00 is reported as UTC with the instant unchanged, so the engine reports what the layout read
  even for an out-of-range offset.
- An input that reads as an integer is taken as a Unix timestamp before any layout, which is the
  instant the reference reports; `Int64(text)` accepts a leading `+` as `strconv.ParseInt` does. Go
  keeps its local zone for that result, so the zone it reports is the machine's, while the port
  reports UTC with offset 0. The "now" fallback the reference's adapters use is not this entry
  point's, because it needs a clock.

**Known differences.**

| Case | Reference (Go 1.22 `time`, the version these notes were traced against) | Rivulet | Impact |
| --- | --- | --- | --- |
| Zone abbreviations | `lookupName` asks the machine's local `Location`, so the offset depends on the instant and on tzdata; the reference's `PST`/`PDT` and `EST`/`EDT` names resolve through Los Angeles and New York at the parsed instant | a fixed table: `PST` −28800, `PDT` −25200, `EST` −18000, `EDT` −14400, `UTC` and `GMT` 0, `GMT±hh` from the name, and the documented fallback 0 for everything else | An abbreviation the machine's zone knows resolves to a different offset here, and a name read inside a daylight-saving period keeps the standard offset instead of the daylight one. A value that reads no zone is not affected, because both read it as UTC |
| Zone name | `Zone()` reports the name of the resolved `*Location`: the machine's zone when it was in effect at the parsed instant, otherwise a fabricated zone named by the name as read | the name as read, which for a bare numeric offset is the empty string | Upstream assertions on `Location().String()` cannot be reproduced; the names are pinned as read, and the two agree when Go fabricates the zone, or when the machine's abbreviation at that instant is the name as read |
| Version of `time` | the reference is Miniflux v2.3.3, whose `go.mod` declares Go 1.26; a current `time` accepts a literal `Z` for all five ISO patterns and rejects an offset hour above 24, an offset minute above 60 or an offset second above 60 | Go 1.22 `time/format.go`, which these notes were traced against: `Z` for the three patterns that carry no seconds, and no range check inside a numeric offset | `+25:00`, `+01:61` and `+01:00:61` match here and are rejected by a current Go, while `+24:00`, `+01:60` and `+01:00:60` match in both because those checks use `>` rather than `>=`. A 1.22-only match outside `checkTimezoneRange`'s −12:00 to +14:00 is reported as UTC with the instant preserved, while `+01:61` is inside the range and keeps its offset. The `Z` half cannot be reached through the catalog, whose 209 layouts have no seconds-bearing ISO pattern |
| Trimming | `strings.TrimSpace`, which also trims Unicode whitespace | Go's `asciiSpace` set | Input that starts or ends with a non-ASCII space is trimmed there and left as it is here |
| A layout that does not match | a `ParseError` naming the layout, the layout element and the value element | no match, because the reference only cares whether a layout matched; the entry point reports the failure after the last layout | The text differs; which layout matched, and the value it read, are the same |

## URL layer (stage 3)

**Matching the reference.**

- The parse order is Go's: the fragment is cut first, then the scheme, then the query, then the
  opaque form or the authority, then the path. The control-character check is made on the part
  before the fragment, which is where Go makes it.
- Only a colon at the start of the value is a failure. An invalid character before the colon means
  there is no scheme, and the value is read as a path; a relative value whose first segment carries
  a colon is the error Go reports for a value like `cache_object:foo/bar`.
- The scheme is lower-cased, as Go lowercases it after reading it, so `RootURL` and the rebuilt
  string report it lower-cased whatever the input case was.
- A raw form is recorded only when it is not already the canonical encoding of the decoded value,
  which is Go's rule for `RawPath`, and `EscapedPath` refuses a recorded form it cannot decode back
  to the decoded value. That is what keeps `http://golang.org/a%2Fb` as it was written while
  `http://golang.org/a%20b` has no recorded form at all.
- The escape classes are the ones `gen_encoding_table.go` builds the table from: alphanumerics and
  the marks `-` `_` `.` `~` are never escaped; the path escapes only `?` from its reserved set, a
  query component escapes all of it, a fragment escapes none of it, and a host allows the
  sub-delimiters plus `:` `[` `]` `<` `>` `"`. A `+` is a space only for a query component.
- `validEncoded` allows the sub-delimiters whatever the mode says, because `shouldEscape` is not
  quite RFC 3986 compliant, which is what decides whether a recorded raw form is used.
- The host is read through the host mode, so a byte at or above DEL is part of it and a percent
  escape may only carry one — except `%25`, which carries the percent sign of a zone identifier —
  and the host is stored decoded, as Go stores it. So `http://foo%c3%a9bar/` parses and reports the
  decoded host.
- The port is read at the first colon for `http` and `https` and at the last one for another scheme,
  which is Go's strict-colon rule with its default on; with the `urlstrictcolons` setting off Go
  takes the last colon there too. A bracket that opens inside the host is refused.
- The user part is checked against the class RFC 3986 §3.2.1 allows, and Go does that after the host
  is read, so a value with both a bad host and a bad user reports the host.
- Query pairs: only `&` separates them, a pair carrying a `;` is an error that `Query()` discards, a
  pair with no `=` is a key with an empty value, and a malformed escape skips the pair. `Encode()`
  writes the keys sorted, with the values of one key in the order they were read.
- `ResolveReference`: a reference that carries an authority is returned as read after its path is
  cleaned; a reference with no path and no query takes the base query and fragment; otherwise the
  path is joined through `resolvePath`, which removes dot segments, pops the whole segment before a
  `..`, keeps a trailing slash when the value ended with a slash or with a dot segment, and does not
  collapse a doubled slash.
- `Hostname` reports a bracketed host without its brackets, and a host whose port is not a number is
  not split at all, which is what Go reports in that case too.
- `ForceQuery` (a value ending with a single `?`) and `OmitHost` (a scheme followed by a slash path
  with no authority) are ported, because both change the string the sanitizer writes back into an
  attribute, and `ResolveReference` does not hand `OmitHost` to the value it resolves.

**Known differences.**

| Case | Reference (`net/url`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Bracketed host | must be a valid IP literal — `netip.ParseAddr` over the unescaped name, with an IPv4 inside brackets refused, and a zone identifier read through its own mode | the bracketed name is read through the host mode and decoded, but only the port after it is checked | A bracketed host that is not an address parses here, so the reader resolves it as a name and the fetcher's address policy sees a host to look up instead of a value it would refuse |
| Percent escapes of bytes that are not valid UTF-8 | the bytes are kept as they are, since a Go string can hold them | a Swift string is valid UTF-8, so a decoded byte that is not a valid sequence becomes U+FFFD | Only an escape of bytes that are not a valid UTF-8 sequence differs; a host can carry such an escape, because the host mode allows an escape of a byte at or above DEL |
| Query parameter count | `ParseQuery` refuses a query above its limit | no limit | A query with more pairs than the limit is parsed here |
| The `*` path | `EscapedPath` returns `*` unescaped | escaped as `%2A` | Only the request-URI form, which the reader never resolves |
| Authority user part | `Userinfo` keeps the username and password decoded separately and re-escapes them when the string is rebuilt | the user part is kept as it was read | The rebuilt string can differ for an escaped user part; nothing in the reader uses the split |
| Error wording | sentences such as `invalid port %q after host` and `missing protocol scheme` | cases naming the offending character, port or escape, with the escape named as Go names it — at most three bytes of it | The text differs; which value fails is the same, and the reader acts on the failure, not on the text |

## HTML sanitizer (stage 3)

**Matching the reference.**

- The sanitizer does not read through SwiftSoup, which the stage 3 plan named for it. The output
  the reference writes is the string it builds itself — the element name, then the attributes in
  the order they were read — so attribute order, name lowercasing, entity decoding, the raw-text
  states and the open-element depth guard have to be the port's own. SwiftSoup does not expose the
  attributes it parsed (`Node.attributes` is internal to the module), it has no depth guard at all,
  and its tree builder is not the one the reference's rules are read against. SwiftSoup is still the
  dependency `EntryText` uses.
- The tokenizer and the insertion modes are traced against `golang.org/x/net/html` v0.57.0
  (BSD-3-Clause), the version `miniflux/go.mod` pins, which is what the reference parses with.
  `Tests/RivuletCoreTests/HTMLTokenizerTests.swift` pins the tokenizer: the comment state is entered
  only through the two dashes of `<!--`, and a comment closes only after two dashes (`-->` or
  `--!>`), so a `>` inside its data is data; a doctype, a processing instruction and any other `<!`
  or `<?` close at the first `>`. The data of those tokens is not observable through the output,
  because the renderer writes nothing for a comment, so the two rules that decide where the data
  ends — the `>` that is the whole data, and the trailing dashes at the end of the input — are
  asserted through the tokenizer itself. A tag name, an attribute key and an attribute value have
  NUL replaced with U+FFFD, which `TagName` and `TagAttr` do, while a text token has it removed by
  the insertion mode, because the tokenizer flags only the raw-text, comment and doctype states as
  converting; the key and the name are pinned through the tokenizer, since a name carrying U+FFFD is
  never in the allowlist. A named reference without its semicolon is resolved outside the attribute
  mode only, and the semicolon stays part of the name because the reader is already past the
  character it stopped on, which a name outside the 106 short names shows. A duplicate attribute
  name is kept once. `readTagAttrVal` skips whitespace before the `=`, and a solidus after the `=`
  is the unquoted value. `>`, `<` and a nested tag inside a raw state are data, which the content of
  the two raw states that are still written (`title`, `textarea`) shows.
  `Tests/RivuletCoreTests/SanitizerTests.swift` pins what the insertion modes answer with: `</p>`
  with no open `p` in `buttonScope` inserts an empty one, and `</br>` is read as a start tag. Only
  `hr` and the block list close an open `p` — `button` does not, and `br`, `img` and `wbr` do not,
  and `table` pops `p` only outside quirks mode, which is never the case on the reference's path.
  `td` and `th` outside a table are not elements at all, while inside one the escaped attribute
  value is written; `tbody` is inserted inside a table but is not in the allowlist, so it is
  invisible in the output, and `</table>` switches back to the insertion mode for the body, so
  content after it is not table content. A newline at the start of a `pre` or `listing` block is
  dropped when it is the first thing in the data as the token was read, before the NUL is removed.
  The escape forms are `&#34;`, `&#39;` and `&#13;`, pinned in text and in an attribute value. The
  scope walk stops at the `defaultScopeStopTags` and at the scope's own stop tags, which is what
  `buttonScope` answers with for a `p` inside a `button` and what `listItemScope` answers with for
  an `li` under an inner list, whose stop tags are `ol` and `ul`. An end tag outside the block list
  walks the stack and stops at the first special element, which is a different set from the stop
  tags: `p` is special but is not a default stop tag, and `span` is neither, so a `</span>` inside a
  `p` is ignored and the text that follows stays in the `p`. A start tag or an end tag that the
  current table mode does not name is processed by the rules for the body at the insertion point, so
  an `img` inside a cell is written into the cell and `</p>` puts an empty `p` there.
- The srcset descriptor rules are ported, including the two that decide the string written back: the
  integer descriptor is read through `ParseUint(value, 10, 0)`, whose range is the whole unsigned
  64-bit value, and the density is written with `strconv.FormatFloat(value, 'g', -1, 64)`'s rule —
  the shortest digits that round-trip, the exponent form when the decimal exponent is below -4 or at
  least 6, and the sign of a negative zero, which the number rule accepts. Both are pinned by
  `SrcSetParserTests`.
- The entity table is the data `x/net/html` builds from the HTML5 named character references,
  generated from the module-cache copy at v0.61.0 (`miniflux/go.mod` pins v0.57.0), and its shape is
  pinned by `HTMLTokenizerTests`. The `entity` map has 2138 entries, 106 of them without a
  semicolon, and every one of those 106 resolves to the value its semicolon form resolves to, so the
  table stores the 2032 semicolon forms once and the short names as a set. The 93 `entity2` entries
  are kept apart because they resolve to two code points. The XML reader's table is `encoding/xml`'s
  smaller HTML4 set, so the two tables are kept apart rather than merged.

**Known differences.**

| Case | Reference (`golang.org/x/net/html`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Foster parenting | content the table modes cannot take is attached to the parent of the table, so it is written before the table | the insertion point is the open element, so it is written inside the table | This is the subset boundary: no case in the reference corpus changes what the sanitizer writes because of it, but real feeds can nest content inside a table here where the reference moves it out |
| Active formatting elements and the adoption agency | a formatting-element list and the adoption agency algorithm, which can move a node into or out of an element | not ported | Markup such as `<p><em>x</p>y</em>` nests differently, so the output differs; nothing in the corpus covers it |
| Caption, column-group and nested-table modes, and the scope markers | each mode has its own rules, including the markers the scope checks stop at | the table modes are the three scopes `clearStackToContext` answers for, with the implied `tbody` and `tr`; a section start tag pops the open `tbody`/`thead`/`tfoot` before it is reprocessed, and a cell closes for the names `inCellIM` lists | A `caption`'s own mode and a nested table are not modelled, so markup that switches into them is attached to the insertion point instead |
| Text inside a table | only whitespace text is added to the table element; anything else is foster parented | added to the insertion point | Same for whitespace; non-whitespace text can be inside the table here |
| Comment nodes | kept as nodes in the tree | not recorded at all | None, because the renderer writes nothing for them; the tree is the shape the sanitizer sees |
| A heading start tag | pops an open `h1`–`h6` before the new heading is inserted | only the `p` pop is ported | `<h1>a<h1>b</h1>` nests the second heading inside the first here |
| `li`, `dd` and `dt` start tags | pop an open ancestor of the same kind, then `p` | the `p` pop is ported, the ancestor loop is not | `<ul><li>a<li>b</ul>` keeps the second item inside the first here; the end tag for `li` is ported and uses `listItemScope` |
| A second `form` start tag | ignored while `p.form` is still set | inserted | None, because `form` is not in the allowlist and only its content is written; the string is the same either way |
| The leading newline of raw text | `textIM` drops it for `textarea` and `title` | dropped for `pre` and `listing` only | `<textarea>\nx` keeps the newline here |
| A self-closing start tag in foreign content | pops the element it opened | the token kind is read, the insertion effect is not | `<math/>x` nests here instead of closing `math`; the check also compares against the last *saved* attribute, where the port tracks every value read |
| A `<![CDATA[` | a CDATA token inside foreign content only, which `AllowCDATA` answers for | a bogus comment that closes at the first `>` | `<math><![CDATA[x]]>` writes `x` in the reference and nothing here |
| Script escaping states | the script data can end at a different position through the escaping states | the raw state ends at the end tag | Nothing is written for `script`, `style` or `noscript`, so the difference is only where the token ends |
| Content in `head` | read through the insertion mode for the head, so markup there is not part of the node the renderer walks | `html` and `head` do not put a node on the tree, so it is read in the body | `<head><title>x</title></head>` writes `x` here and nothing in the reference |
| Implied end tags | `generateImpliedEndTags` pops `p`, `li`, `dd` and `dt` before `hr` and `button` in some cases | the open `p` is popped, which is the same answer while the stack is well formed | A list item or definition inside a `p` nests through the ancestor loop, which is the row above |
| Positions and counts | the tokenizer measures bytes and the character walks count runes | `Character` graphemes | A combining sequence or a ZWJ sequence is one position here where the reference counts more; the `&#13;&#10;` pair is one instance of that |
| The Vimeo `dnt=1` append | the link is written as it was read | rebuilt from the parsed parts | A query that is not already in the canonical form is re-encoded, so the string differs; one that is, is written the same |
| `escape` and `unescape` | `&#34;`, `&#39;` and `&#13;`, and the no-semicolon fallback outside attribute mode | the same, pinned by tests, for a lone CR | A decoded `&#13;&#10;` is one `Character` grapheme in Swift, so the pair is written raw where the reference writes `&#13;` and a newline |
