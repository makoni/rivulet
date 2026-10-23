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
- Undefined positions of single-byte encodings (for example windows-1252 `81`, ISO-8859-3 `A5`)
  become U+FFFD, like the reference decoders.
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
| Invalid sequences in GBK/GB18030/Big5/Shift_JIS/EUC-KR/ISO-2022-JP | U+FFFD per maximal subpart, which can cover several bytes | platform decoder, then glibc `iconv` (which reports one error per stop), then a windowed rescan | Corrupt spans can differ in the number and placement of U+FFFD; valid text is unaffected |
| EUC-JP on Linux | decoded by `x/text` | Foundation returns `nil` for every input, so the glibc `iconv` fallback decodes it | Same result for valid documents; pinned by a test |
| Single-byte tables | `x/text` `charmap`, so `iso-8859-8-i` keeps its own visual table and `iso-8859-6` its own | CoreFoundation resolves the IANA name, which can map an alias to a different table (for example `iso-8859-8-i`) | Only exotic input differs; no fixture covers it |
| `<meta>` prescan | full HTML tokenizer, with character references unescaped in attribute values | tag scanner (comments, quoting, attribute order, 1024-byte window) | Malformed markup the tokenizer recovers from can end the scan; a label written as an entity is not resolved |
| Content-type `charset` parameter | `mime.ParseMediaType` | direct parameter scan | Some malformed headers yield a charset where the reference falls through to detection |

None of these differences is observable on the ported fixture corpus: all fixture assertions the
reference makes are reproduced. Valid documents in a legacy encoding decode identically.
