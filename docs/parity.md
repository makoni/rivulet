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
| Bare `io.EOF` | returned as it is when nothing is open, such as after a comment at the top level | the same `unexpectedEOF` case | Only the message differs; the reader reports it as one failure |
| `translate`'s `DefaultSpace` | falls back to the decoder's `DefaultSpace` for a name with no prefix | not ported, because the reference never sets it, so the fallback assigns the empty string | None |
| `AutoClose` | a list the reference can be given, which invents end tags for unclosed elements | not ported, because the reference never sets it | None |
| `pushEOF` and `popEOF` | used only for types that implement `UnmarshalXML`, which Miniflux never implements | not ported; the reader marks where `Decode` stops and reports reaching it | None |
