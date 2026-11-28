# Clients

The clients Rivulet is checked against, how to connect each one, and what has been verified.

The calls each client makes were read from its own source at a named commit (Reeder Classic, which
is closed source, from its documentation) and are recorded as calling sets in
`Tests/RivuletIntegrationTests/CallingSets/`. `ClientSequenceReplayTests` replays the recorded calls
against the served app on every `swift test`; `replayed.txt` in the same directory pairs each call
with the test that replays it, or the reason it cannot be replayed.

Manual walks with the real apps are done with `Scripts/client-run.sh`, which serves a seeded
instance behind a logging proxy and records every request the app sends (see the script header).
The checks still open before the release are in the 0.1.0 release checklist issue (#130).

## Logging in

- **Google Reader API and Fever** use the *integration credentials* set with
  `rivulet integration-credentials`, not the account password.
- **Miniflux REST v1** uses the account password (basic auth) or an API key from
  `rivulet create-api-key` (`X-Auth-Token`).

## Summary

| Client | API | Calls recorded | Replayed in tests | Walked with the real app |
| --- | --- | --- | --- | --- |
| NetNewsWire | Google Reader | 11 | 11 | yes |
| FeedFlow | Google Reader | 11 | 11 | yes |
| NewsFlash | Fever | 14 | 13 | yes |
| Capy Reader | Google Reader + Miniflux REST v1 | 36 | 31 | yes, except deleting a category over REST v1 (#130) |
| Reeder Classic | Fever | — (closed source) | — | partly; four items left (#130) |

A recorded call that is not replayed is either one with no route yet (see Capy Reader) or NewsFlash's
`items?with_ids` size guard, which the app applies before it sends.

## NetNewsWire — Google Reader API

Source: `Account/Sources/Account/ReaderAPI/ReaderAPICaller.swift` at `ab5421f5`.

Setup: Settings → Accounts → add an account → Self-hosted → **FreshRSS** (there is no generic
"Reader API" type), with the integration credentials. Give the address as host and port only: the
app appends the endpoint paths itself.

Notes: it logs in without `output`, so it reads the plain-text login answer. It sends item ids in
two forms — unpadded hex to `stream/items/contents`, zero-padded to `edit-tag` — and both are
read. Creating a folder sends nothing until a feed is moved into it.

## FeedFlow — Google Reader API

Source: `feedSync/greader/.../GReaderClient.kt` at `75d1c0ee`.

Setup: Settings → Feeds & accounts → Accounts → the sync account for **Miniflux** (FeedFlow talks
the Google Reader API to it), with the integration credentials. The app logs in first and then sends
the token the login returned.

Notes: it reads items from `reader/api/0/stream/contents`, which Miniflux has no route for either,
so both answer with the catch-all `[]` and the app reads an empty page rather than failing. Its
folder delete goes to `edit-tag` with no add/remove pair. It re-fetches the token when an answer
carries `X-Reader-Google-Bad-Token: true`. It asks for `n=15000`, above the page-size clamp.

## NewsFlash — Fever API

Setup: Settings → Sync → **Fever**, with the integration credentials. The base URL must include
`/fever`; without it the app reaches the root and gets a 404.

Notes: the API key is the MD5 of `name:password`. NewsFlash's decoder rejects `null` for `groups` and
`favicons`, so Rivulet writes `[]` for empty lists where Miniflux writes `null` (`docs/parity.md`).

## Capy Reader — Google Reader API and Miniflux REST v1

Setup: a Google Reader-compatible account with the integration credentials, or a **Miniflux**
account with the account password or an API key. The app holds one active account at a time.

Notes: the REST v1 half is the 20 endpoints listed in `docs/plan/stage-10-rest-v1.md`. Four of its
calls have no route yet — `GET /v1/categories/{id}/entries`, `GET /v1/icons/{id}`,
`POST /v1/entries/{id}/save` and `PUT /v1/categories/{id}/mark-all-as-read` (#121) — and answer the
router's 404. The app also declares `GET /v1/categories/{id}`, which Miniflux has no GET pattern for
either (it answers 405; Rivulet answers 404 — `docs/parity.md`).

## Reeder Classic — Fever API

Setup: the Fever form, with the server address and the integration credentials.

Walked: log in, groups, feeds, unread and saved ids, item pages with `since_id`, mark an item read,
unread and saved. Not yet walked (#130): `favicons`, `links`, mark a feed read before a time, mark a
group read.
