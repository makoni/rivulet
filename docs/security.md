# Security checklist (stage 7)

The checklist the stage names, taken sub-item by sub-item. For each rule: what the rule is, where
the port reads it, which test can fail on it, and what no test can show. A rule a patch cannot flip
is named here rather than asserted — that is the same agreement the suite headers keep, and a pin
that cannot fail on the rule it names is not a pin.

Method: each rule was read in the port and in the reference at `c4d54f87`; where the port could
express it as a pin, the pin was shown failing on the rule by patching production code, rebuilding
and reverting byte-identically. 8 pins and 7 probes across five suites landed with this pass, and
the probes are named in the suite headers. `docs/testing.md` records the method; the pins that
already existed before this pass are named here by the rule they pin, and a count is given only
where this pass added one.

## The finding this pass closed — a repeated response header name

Rule: when a response name appears twice, the value read is the first one. The reference keeps a
list per name (`textproto.ReadMIMEHeader` appends in the order the values arrive) and `Header.Get`
answers the first of that list, so the first `Location` is the hop the client follows. The key is
the canonical spelling `CanonicalMIMEHeaderKey` builds, so `location` and `Location` are one name.

Where the port reads it: `Fetcher.send` builds the header map from what the client delivered,
keeping the first value for a name compared without case. Before this pass it kept the last value,
which is the divergence the pins close; the value is stored in the spelling the wire gave, which the
reference would have canonicalized.

Which test can fail on it: `RepeatedResponseHeadersTests` — 3 pins and 2 probes: first-wins for a
repeated name, one name written two ways is one entry, and the first `Location` is the hop taken.
The stub server writes headers as ordered pairs for these (`Behavior.headerPairs`), because
`Behavior.headers` is a dictionary and cannot hold two values for one name. Red before the fix: the
repeated-name pin and the hop pin failed on the last-wins rule; the case pin as first written
passed, for the reason its header names — a case-insensitive lookup answers one of the two entries,
and dictionary order is not fixed — so it now reads the count first, and under the pre-fix rule,
which is its probe, that count fails. The first probe is the pre-fix rule itself, so all three pins
are red on the rule they name.

What this pass cannot pin: which spelling of the name the one entry holds; both values for one name,
which the port does not model; the canonical spelling a key gets upstream; the case rules of the
client's decoder, which decides the name before this code sees it; the header value of a hop that is
not the last one, because `fetch` returns the last response, which is why the hop pin reads the path
the stub was asked for; and a response whose two values are identical, which no wrong rule can be
caught on.

## SSRF

Rule: a direct hop may connect only to a public address. The set refused is the reference's:
private, loopback, link-local, multicast, unspecified and the RFC 6598 shared address space; an
answer that is not an address counts as non-public, like Go's `nil`. A 4-in-6 address is classified
through its IPv4 form, as Go unmaps it. The escape hatch is the environment flag, off by default. A
hop to a proxy is not checked, because the reference installs its dialer `Control` callback on the
direct dialer only and the proxy resolves the target.

Where the port reads it: `NetworkAddressPolicy.allows`, called by `Fetcher.resolveAndPin` for every
direct hop — the seam's answers for a name, or the URL's own address when it already carries one.
The client is then pinned with `dnsOverride` to an address validated when it was built, so a later
lookup cannot steer the connection; that is the guarantee the reference's callback gives by another
mechanism, and it is the reason the check is not a lookup at dial time here. A scheme the client
will not serve is refused before a connection, which is the same guard the reference has for a
redirect to a scheme its transport cannot dial.

Which tests can fail on it: `NetworkAddressPolicyTests` — the classes, the nil case and the unmap,
the ported `TestIsNonPublicIP`; `AddressResolutionTests` — one lookup per hop, every answer
validated before connecting, the pin equal to the answer; `FetcherSecurityTests` — the refusal with
the hatch off and the same target admitted with it on, the seam consulted for each hop, the policy
running on the hop that took its client from the cache, the proxy hop skipped, and the ports the
reference assumes for a proxy URL that names none.

What this pass cannot pin: a refusal on a cached hop, because the only address the stub can be
reached through is loopback, which a denying policy refuses on the first hop too — so the cached-hop
pin reads the seam's call count instead of an answer; that the connection used the pinned address
rather than re-resolving, which is read through the names the seam was asked for, not through the
socket; the reference's reading of the environment proxy, which this port does not read at all, so
there is no counterpart to pin; and the order between the policy and the client cache, which no
patch can show because the cached client keeps the address it was built with.

## Size and time caps

Rule: the response body is capped at `HTTP_CLIENT_MAX_BODY_SIZE` (15 MiB default), counted on the
bytes the decoder produces, because the reference's `MaxBytesReader` wraps the decompression reader.
There is no limit on how far a stream may expand upstream, and the port's own ratio guard was
removed for the same reason: it refused a body the reference would have read. The time rule is one
deadline shared by all hops (`HTTP_CLIENT_TIMEOUT`, 20 seconds default), covering connection,
redirects and body reading together; the connect timeout is 10 seconds, the reference's dialer
value. The redirect cap is 10, with the boundary divergence recorded in `docs/reference-notes.md`.
The numeric options are validated as at least 1, and an absurd duration is clamped rather than
trapping. In the parsing path, the open-element stack limit of 512 and the `TruncateHTML` limit
counted per code point are the caps the sanitizer reads.

Where the port reads them: `FetcherOptions` for the values, `ResponseAccumulator` for the body cap,
one `NIODeadline` for the deadline, the redirect loop in `Fetcher.send`, `Fetcher.amount(for:)` for
the clamp, and the sanitizer's depth limit and text limit.

Which tests can fail on them: `FetcherHostileInputTests` — 4 pins and 5 probes, which is the pass
that removed the ratio guard; `FetcherTests` — the cap at a configured size, the deadline covering
the body after the head, the deadline not restarting per hop, the redirect loop capped, a redirect
status with an empty `Location` returned as the response, and a scheme the client refuses;
`FetcherOptionsTests` — the defaults, the ≥1 validators, the accepted boolean words;
`FetcherTimingTests` — the clamp at both ends; `SanitizerHostileCorpusTests` — the two cases
mirroring `TestDeeplyNestedpage`, where the reference's own parse recovers the limit as an error, so
a chain one past it answers with nothing; `TruncateHTMLTests` — the limit counted per code point,
not per Swift grapheme.

What this pass cannot pin: the connect timeout as a limit of its own, because a pin would need a
client-creation seam or a listener that never accepts, and the plan has neither — the value is
stated in the code comment; the response header-block size, because this port reads no limit of its
own: Go's `DefaultMaxHeaderBytes` is a server-side limit, so what this port has is the dependency's
cap, and a pin here could only read the dependency's number, not a rule the port has; what the
accumulator is given, since no patch can change what the pipeline hands it, so the cap rule is read
through the guard being absent; the fixture encoder, checked against `gunzip` by hand; memory, which
no pin reads, so the budget is a documented number; the numbers of another machine, which the timed
pin reads as a bound; and which entry the client cache's trim closes is not observable through a
fetch — that pin reads the cache through an internal accessor, together with the cap staying at 8
after a checkout that goes over it (2 pins and 2 probes in `FetcherClientCacheTests`), and the clock
tie between entries expiring at the same instant is not pinned either.

## Auth behavior

Rule: what the pins name. The bcrypt cost is the reference's 10, the marker the reference writes is
`$2a$`, a plaintext longer than 72 bytes is refused on the hash path, and the compare path has no
length check and reads at most the first 72 key bytes, so a longer plaintext that shares those bytes
answers as a match. The Google Reader token is the name, a slash and the lowercase hex of
`hmac_sha256(key: name + stored hash, message: empty)`; the structure rule reads exactly two parts
with empty parts kept. The guard that an empty name ends the login before any read runs first. The
Fever lookup lowercases both sides, the Google Reader read compares the name as read, and both
answer nothing when no row matches; the admin flag is what `create-admin` writes, and the existence
read runs before any rule.

Where the port reads it: `BcryptHasher`, `GoogleReaderToken`, the auth middleware of
`Sources/RivuletApp/Routes`, `UserRepository` and `IntegrationRepository` reads.

Which tests can fail on them: `BcryptHasherTests` — cost, stored value, verification, random salt,
the 72-byte guard, the compare path, the marker direction; `GoogleReaderTokenTests` — the goldens
from the reference's own run, the lowercase hex, the slash, the structure rule; `ClientAuthTests` —
the two reads and the control pin that shows the account lookup lowercases what it is given while
these do not; `GoogleReaderAuthTests` — the field names, the two shapes, the guards, the header
shape rules, the two 401 shapes; `UserValidationTests` and `IntegrationValidationTests` — the
character class read per Unicode scalar, the byte-counted minimum, the order of the two duplicate
checks, the per-user exclusion, the rule that a blank password read keeps the stored value.

What this pass cannot pin: the timing form of the constant-time compare, which the reference reads
through `crypto/subtle` — a patch here that compared with `==` would answer the same for every input
the suite can build, so the form is stated in the code comment; a plaintext that holds a NUL byte,
which is the dependency's divergence, because Vapor's C implementation measures the key with
`strlen` — `docs/parity.md` records it, and no patch of this port can change the measurement; the
marker this port writes; the single-row limit of the reads; the wording of the reported failures;
the guard's password half, which answers 401 for every input this suite can build; and the role
model, because the reference's `IsAdminUser` check gates its API user endpoints and this port has no
such endpoint yet — the admin flag is read by `create-admin` and by `list`, and nothing treats it as
a gate, so there is nothing to pin.

## Sanitizer bypass surface

Rule: the tag allowlist and the per-tag attribute lists, the three mandatory attributes, the scheme
allowlist, the tracking-parameter removal, the data URL and in-document anchor kept as read, the
one-pixel, script and hidden elements skipped with their content, and the depth limit. The value the
scheme check reads is the value the tokenizer unescaped, so membership in the entity table is part
of the rule before the scheme is read — `http&colon;example.org` is checked as `http:example.org`,
and a case pinned for it writes the link with the decoded address. `isPositiveInteger` is
`strconv.Atoi`, which reads a leading `+` as part of the number, so `width="+10"` is kept. Both
expected values are the reference's own output, produced by running it at `c4d54f87` on Go 1.26.0
through the method `docs/testing.md` records; the port matches them today, so both are red only
under their probes.

Which tests can fail on them: `SanitizerHostileCorpusTests` — 146 inputs, each with the reference's
output and the rule it pins, 145 from stage 3 and the entity-table case this pass added (1 pin and 1
probe, the probe removing `colon;` from `HTMLEntityTable.swift`); `SanitizerTests` — the sign as
`Atoi` reads it (1 pin and 1 probe); `SanitizerTableModeTests` — the two insertion-mode rules;
`HTMLTokenizerTests` — the NUL removal and the entity decoding at the token layer;
`URISchemeAllowlistTests` — the allowlist and the case-insensitive comparison.

What this pass cannot pin: content inside `math` or `svg`, which the reference writes through the
foreign-content rules this port does not have; the entity table as a whole, because a name the port
resolves to the same value by another route is pinned by no case; a NUL in the tokenizer text, which
is read through the tokenizer itself rather than through the sanitizer output; the fuzz target
`FuzzSanitizer`, whose expectation needs a fuzz harness Swift Testing has neither; and the values
the reference answers from `config.Opts`, which the corpus pins only through the option defaults.

## Dependency audit

Method: the GitHub Advisory DB, which is the one that covers the Swift ecosystem — OSV has no Swift
ecosystem entry. Each of the 36 pins in `Package.resolved` was queried with `affects` on 2026-11-07.
Twenty-seven advisories came back over seven packages, and every first-patched version is below the
pin this repository holds, so no pin is affected. A pin with no advisory is not listed.

| Package | Pin here | Advisories | Highest first patched |
| --- | --- | --- | --- |
| swift-nio | 2.104.0 | 5 | 2.100.0 |
| swift-nio-extras | 1.35.1 | 2 | 1.34.1 |
| swift-nio-http2 | 1.46.0 | 10 | 1.44.0 |
| swift-nio-ssl | 2.37.5 | 1 | 2.4.1 |
| async-http-client | 1.36.2 | 1 | 1.13.2 |
| vapor | 4.122.2 | 7 | 4.90.0 |
| swift-asn1 | 1.7.3 | 1 | 1.3.1 |

Two of them touch the rules this document names. The unbounded HTTP/1 header block
(GHSA-rj37-6j9x-74q6, CVE-2026-28980, high) is the size rule named as unpinnable above: this port
reads no header-block limit of its own, so what it has is the cap the dependency added at 2.100.0,
which the pin is above — a pin here could only read the dependency's number, not a rule the port
has. The decompressor ratio limit bypass through an inflated `Content-Length` (GHSA-6ph5-fww6-vfwv,
CVE-2026-28975, medium) belongs to a guard this port does not have at all, because the ratio guard
was removed: the body cap is the only limit, which is upstream's shape, and the fix is what the
pinned version carries.

## Rules checked by hand, not by a pin

That no fixture, test or document in the repository carries a secret, a token or a personal feed
list; that the sanitizer allowlists were not widened to make a test pass; that the escape hatch is
off by default and every test that turns it on names why; and that no fetch path sleeps or fetches
inside a command that should not. These are the agreement in `AGENTS.md` under Safety, and they are
checked by reading the code, not by a pin.
