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
