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
  `gb2312` → GBK, `utf-16` → little-endian).
- A document that is already valid UTF-8 is never converted, whatever label it declares; a wrong
  prolog cannot double-encode it. An unknown label is only an error when the bytes are not valid
  UTF-8.
- Detection follows the reference order: BOM → content-type `charset` → `<meta>` prescan over the
  first 1024 bytes → "looks like UTF-8" heuristic → `windows-1252` default.
- Undefined positions of single-byte encodings (for example windows-1252 `81`, ISO-8859-3 `A5`)
  become U+FFFD, like the reference decoders.
- A UTF-16 byte-order mark is kept in the output as U+FEFF, matching the reference's
  `IgnoreBOM` decoder policy.
- `x-user-defined` (high bytes → U+F780–U+F7FF) and the replacement encoding (one U+FFFD) are
  implemented directly.

**Known differences.**

| Case | Reference (`x/text`) | Rivulet | Impact |
| --- | --- | --- | --- |
| Big5 byte `80` | U+FFFD | U+0080 (ICU/Foundation) | A private byte survives; the reference drops it |
| Big5 byte `FF` | U+FFFD | U+F8F8 (ICU private use) | An invalid byte becomes a PUA character instead of U+FFFD |
| Invalid sequences in GBK/GB18030/Big5/Shift_JIS/EUC-KR/ISO-2022-JP | U+FFFD per invalid sequence; exact placement is decoder-specific | platform decoder, then glibc `iconv`, then a windowed rescan — each replaces what it rejects with U+FFFD | Corrupt spans can differ in the number and placement of U+FFFD; valid text is unaffected |
| EUC-JP on Linux | decoded by `x/text` | Foundation returns `nil` for every input, so the glibc `iconv` fallback decodes it | Same result for valid documents; pinned by a test |
| `<meta>` prescan | full HTML tokenizer | tag scanner (comments, quoting, attribute order, 1024-byte window) | Malformed markup the tokenizer would recover from can end the scan early |
| Content-type `charset` parameter | `mime.ParseMediaType` | direct parameter scan | Some malformed headers yield a charset where the reference falls through to detection |

None of these differences is observable on the ported fixture corpus: all fixture assertions the
reference makes are reproduced. Valid documents in a legacy encoding decode identically.
